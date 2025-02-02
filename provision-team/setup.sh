#!/bin/bash

# set -euo pipefail
IFS=$'\n\t'

usage() { echo "Usage: setup.sh -i <subscriptionId> -l <resourceGroupLocation> -n <teamName> -e <teamNumber> -r <recipientEmail> -c <chatConnectionString> -q <chatMessageQueue> -u <azureUserName> -p <azurePassword> -j <bingAPIkey> -t <tenantId>" 1>&2; exit 1; }
echo "$@"

declare subscriptionId=""
declare resourceGroupLocation=""
declare teamName=""
declare teamNumber=""
declare azureUserName=""
declare azurePassword=""
declare recipientEmail=""
declare chatConnectionString=""
declare chatMessageQueue=""
declare provisioningVMIpaddress=""
declare bingAPIkey=""
declare tenantId=""
declare appId=""

# Initialize parameters specified from command line
while getopts ":a:c:i:l:n:e:q:r:t:u:p:j:" arg; do
    case "${arg}" in
        a)
            appId=${OPTARG}
        ;;
        c)
            chatConnectionString=${OPTARG}
        ;;
        i)
            subscriptionId=${OPTARG}
        ;;
        l)
            resourceGroupLocation=${OPTARG}
        ;;
        n)
            teamName=${OPTARG}
        ;;
        e)
            teamNumber=${OPTARG}
        ;;
        q)
            chatMessageQueue=${OPTARG}
        ;;
        r)
            recipientEmail=${OPTARG}
        ;;
        t)
            tenantId=${OPTARG}
        ;;
        u)
            azureUserName=${OPTARG}
        ;;
        p)
            azurePassword=${OPTARG}
        ;;
        j)
            bingAPIkey=${OPTARG}
        ;;
    esac
done
shift $((OPTIND-1))

# Check if kubectl is installed or that we can install it
type -p kubectl
if [ ! $? == 0 ]; then
    if [[ ! $EUID == 0 ]]; then
        echo "kubectl not found, install and re-run setup."
        exit 1
    fi
fi

type -p sqlcmd
if [ ! $? == 0 ]; then
    echo "sqlcmd not found, install and re-run setup."
    exit 1
fi

randomChar() {
    s=abcdefghijklmnopqrstuvxwyz0123456789
    p=$(( $RANDOM % 36))
    echo -n ${s:$p:1}
}

randomNum() {
    echo -n $(( $RANDOM % 10 ))
}

randomCharUpper() {
    s=ABCDEFGHIJKLMNOPQRSTUVWXYZ
    p=$(( $RANDOM % 26))
    echo -n ${s:$p:1}
}

if [[ -z "$teamNumber" ]]; then
    echo "Using a random team number since not specified."
    teamNumber="$(randomChar;randomChar;randomChar;randomNum;)"
fi

declare resourceGroupTeam="${teamName}${teamNumber}rg";
declare registryName="${teamName}${teamNumber}acr"
declare clusterName="${teamName}${teamNumber}aks"
declare keyVaultName="${teamName}${teamNumber}kv"
declare sqlServerName="${teamName}${teamNumber}sql"
declare sqlServerUsername="${teamName}${teamNumber}sa"
declare sqlServerPassword="$(randomChar;randomCharUpper;randomNum;randomChar;randomChar;randomNum;randomCharUpper;randomChar;randomNum)pwd"
declare sqlDBName="mydrivingDB"
declare jenkinsVMPassword="$(randomChar;randomCharUpper;randomNum;randomChar;randomChar;randomNum;randomCharUpper;randomChar;randomNum)pwd"
declare jenkinsURL="jenkins${teamName}${teamNumber}"
declare zipPassword=$(< /dev/urandom tr -dc '!@#$%_A-Z-a-z-0-9' | head -c${1:-32};echo;)

echo "=========================================="
echo " VARIABLES"
echo "=========================================="
echo "subscriptionId            = "${subscriptionId}
echo "resourceGroupLocation     = "${resourceGroupLocation}
echo "teamName                  = "${teamName}
echo "teamNumber                = "${teamNumber}
echo "keyVaultName              = "${keyVaultName}
echo "resourceGroupTeam         = "${resourceGroupTeam}
echo "registryName              = "${registryName}
echo "clusterName               = "${clusterName}
echo "sqlServerName             = "${sqlServerName}
echo "sqlServerUsername         = "${sqlServerUsername}
echo "sqlServerPassword         = "${sqlServerPassword}
echo "sqlDBName                 = "${sqlDBName}
echo "jenkinsVMPassword         = "${jenkinsVMPassword}
echo "jenkinsURL                = "${jenkinsURL}.${resourceGroupLocation}.cloudapp.azure.com:8080
echo "recipientEmail            = "${recipientEmail}
echo "chatConnectionString      = "${chatConnectionString}
echo "chatMessageQueue          = "${chatMessageQueue}
echo "zipPassword"              = "${zipPassword}"
echo "bingAPIkey"               = "${bingAPIkey}"
echo "tenantId"                 = "${tenantId}"
echo "AppId"                    = "${appId}"
echo "=========================================="

#login to azure using your credentials
echo "Username: $azureUserName"
echo "Password: $azurePassword"

if [[ "$tenantId" == "noSP" ]]; then
    echo "Command will be az login --username=$azureUserName --password=$azurePassword"
    az login --username=$azureUserName --password=$azurePassword
else
        echo "Command will be az login --username=$azureUserName --password=$azurePassword --tenant=$tenantId"
    az login  --service-principal --username=$azureUserName --password=$azurePassword --tenant=$tenantId
fi

#set the default subscription id
echo "Setting subscription to $subscriptionId..."

az account set --subscription $subscriptionId

declare tenantId=$(az account show -s ${subscriptionId} --query tenantId -o tsv)

#TODO need to check if provider is registered and if so don't run this command.  Also probably need to sleep a few minutes for this to finish.
echo "Registering ContainerServiceProvider..."
az provider register -n Microsoft.ContainerService

set +e

#Check for existing RG
if [ `az group exists -n $resourceGroupTeam -o tsv` == false ]; then
    echo "Resource group with name" $resourceGroupTeam "could not be found. Creating new resource group.."
    set -e
    (
        set -x
        az group create --name $resourceGroupTeam --location $resourceGroupLocation
    )
else
    echo "Using existing resource group..."
fi

# Verify that the teamConfig dir exist
if [ ! -d "/home/zhaw/team_env" ]; then
   mkdir /home/zhaw/team_env
fi

# Verify that kvstore dir exist
if [ ! -d "/home/zhaw/team_env/kvstore" ]; then
   mkdir /home/zhaw/team_env/kvstore
fi

# Verify that the team dir exist
if [ ! -d "/home/zhaw/team_env/${teamName}${teamNumber}" ]; then
   mkdir /home/zhaw/team_env/${teamName}${teamNumber}
fi

kvstore set ${teamName}${teamNumber} subscriptionId ${subscriptionId}
kvstore set ${teamName}${teamNumber} tenantId ${tenantId}
kvstore set ${teamName}${teamNumber} resourceGroupLocation ${resourceGroupLocation}
kvstore set ${teamName}${teamNumber} teamNumber ${teamNumber}
kvstore set ${teamName}${teamNumber} keyVaultName ${keyVaultName}
kvstore set ${teamName}${teamNumber} resourceGroup ${resourceGroupTeam}
kvstore set ${teamName}${teamNumber} ACR ${registryName}
kvstore set ${teamName}${teamNumber} AKS ${clusterName}
kvstore set ${teamName}${teamNumber} sqlServerName ${sqlServerName}
kvstore set ${teamName}${teamNumber} sqlServerUserName ${sqlServerUsername}
kvstore set ${teamName}${teamNumber} sqlServerPassword ${sqlServerPassword}
kvstore set ${teamName}${teamNumber} sqlDbName ${sqlDBName}
kvstore set ${teamName}${teamNumber} teamFiles /home/azureuser/team_env/${teamName}${teamNumber}
kvstore set ${teamName}${teamNumber} jenkinsVMPassword ${jenkinsVMPassword}
kvstore set ${teamName}${teamNumber} jenkinsURL ${jenkinsURL}.${resourceGroupLocation}.cloudapp.azure.com

az configure --defaults 'output=json'

echo "0-Provision KeyVault  (bash ./provision_kv.sh -i $subscriptionId -g $resourceGroupTeam -k $keyVaultName -l $resourceGroupLocation)"
bash ./provision_kv.sh -i $subscriptionId -g $resourceGroupTeam -k $keyVaultName -l $resourceGroupLocation

echo "1-Provision ACR  (bash ./provision_acr.sh -i $subscriptionId -g $resourceGroupTeam -r $registryName -l $resourceGroupLocation)"
bash ./provision_acr.sh -i $subscriptionId -g $resourceGroupTeam -r $registryName -l $resourceGroupLocation

echo "2-Provision AKS  (bash ./provision_aks.sh -i $subscriptionId -g $resourceGroupTeam -c $clusterName -l $resourceGroupLocation)"
bash ./provision_aks.sh -i $subscriptionId -g $resourceGroupTeam -c $clusterName -l $resourceGroupLocation -a $appId -n $azureUserName -p $azurePassword

echo "5-Clone repo"
bash ./git_fetch.sh -u https://github.com/Azure-Samples/openhack-devops-team -s ./test_fetch_build

echo "6-Deploy ingress  (bash ./deploy_ingress_dns.sh -s ./test_fetch_build -l $resourceGroupLocation -n ${teamName}${teamNumber})"
bash ./deploy_ingress_dns.sh -s ./test_fetch_build -l $resourceGroupLocation -n ${teamName}${teamNumber}

echo "7-Provision SQL (bash ./provision_sql.sh -s ./test_fetch_build -g $resourceGroupTeam -l $resourceGroupLocation -q $sqlServerName -k $keyVaultName -u $sqlServerUsername -p $sqlServerPassword -d $sqlDBName)"
bash ./provision_sql.sh -g $resourceGroupTeam -l $resourceGroupLocation -q $sqlServerName -k $keyVaultName -u $sqlServerUsername -p $sqlServerPassword -d $sqlDBName

echo "8-Configure SQL  (bash ./configure_sql.sh -s ./test_fetch_build -g $resourceGroupTeam -u $sqlServerUsername -n ${teamName}${teamNumber} -k $keyVaultName -d $sqlDBName)"
bash ./configure_sql.sh -s ./test_fetch_build -g $resourceGroupTeam -u $sqlServerUsername -n ${teamName}${teamNumber} -k $keyVaultName -d $sqlDBName

# Save the public DNS address to be provisioned in the helm charts for each service
dnsURL='akstraefik'${teamName}${teamNumber}'.'$resourceGroupLocation'.cloudapp.azure.com'
dnsURLstage='stageakstraefik'${teamName}${teamNumber}'.'$resourceGroupLocation'.cloudapp.azure.com'
echo -e "DNS URL for "${teamName}" is:\n"$dnsURL
echo -e "Staging DNS URL for "${teamName}" is:\n"$dnsURLstage

kvstore set ${teamName}${teamNumber} endpoint ${dnsURL}
kvstore set ${teamName}${teamNumber} staging_endpoint ${dnsURLstage}

echo "9-Build and deploy POI API to AKS  (bash ./build_deploy_poi.sh -s ./test_fetch_build -b Release -r $resourceGroupTeam -t 'api-poi' -d $dnsURL -n ${teamName}${teamNumber} -g $registryName)"
bash ./build_deploy_poi.sh -s ./test_fetch_build -b Release -r $resourceGroupTeam -t 'api-poi' -d $dnsURL -n ${teamName}${teamNumber} -g $registryName

echo "10-Build and deploy User API to AKS  (bash ./build_deploy_user.sh -s ./test_fetch_build -b Release -r $resourceGroupTeam -t 'api-user' -d $dnsURL -n ${teamName}${teamNumber} -g $registryName)"
bash ./build_deploy_user.sh -s ./test_fetch_build -b Release -r $resourceGroupTeam -t 'api-user' -d $dnsURL -n ${teamName}${teamNumber} -g $registryName

echo "11-Build and deploy Trip API to AKS  (# bash ./build_deploy_trip.sh -s ./test_fetch_build -b Release -r $resourceGroupTeam -t 'api-trip' -d $dnsURL -n ${teamName}${teamNumber} -g $registryName)"
bash ./build_deploy_trip.sh -s ./test_fetch_build -b Release -r $resourceGroupTeam -t 'api-trip' -d $dnsURL -n ${teamName}${teamNumber} -g $registryName

echo "12-Build and deploy User-Profile API to AKS  (# bash ./build_deploy_user-profile.sh -s ./test_fetch_build -b Release -r $resourceGroupTeam -t 'api-userprofile' -d $dnsURL -n ${teamName}${teamNumber} -g $registryName)"
bash ./build_deploy_user-java.sh -s ./test_fetch_build -b Release -r $resourceGroupTeam -t 'api-user-java' -d $dnsURL -n ${teamName}${teamNumber} -g $registryName

echo "13-Build and deploy Tripviewer website to AKS (# bash ./build_deploy_tripviewer.sh -m ${teamName}${teamNumber} -d $dnsURL -j $bingAPIkey)"
bash ./build_deploy_tripviewer.sh -m ${teamName}${teamNumber} -d $dnsURL -j $bingAPIkey

echo "14-Build and deploy the simulator (# bash Usage: build_deploy_simulator.sh -n ${teamName}${teamNumber} -q 18000 -d $dnsURL -t <image tag optional>)"
bash ./build_deploy_simulator.sh -n ${teamName}${teamNumber} -q '18000' -d $dnsURL

echo "15-Deploy Jenkins VM (# bash ./deploy_jenkins.sh -g $resourceGroupTeam -l $resourceGroupLocation -p $jenkinsVMPassword -u $jenkinsURL) "
#bash ./deploy_jenkins.sh -g ${resourceGroupTeam} -l ${resourceGroupLocation} -p ${jenkinsVMPassword} -u ${jenkinsURL}

echo "16-Check services (# bash ./service_check.sh -d ${dnsURL} -n ${teamName}${teamNumber})"
bash ./service_check.sh -d ${dnsURL} -n ${teamName}${teamNumber}

echo "17-Clean the working environment"
bash ./cleanup_environment.sh -t ${teamName}${teamNumber} -p $zipPassword

echo "18-Expose the team settings on a website"
bash ./run_nginx.sh

#This line is not valid when using a self-provisioning.
if [ "${chatConnectionString}" == "null" ] && [ "${chatMessageQueue}" == "null" ]; then
    echo "OpenHack credentials are here: http://$provisioningVMIpaddress:2018/teamfiles.zip with zip password $zipPassword"
else
    echo "19-Send Message home"
    provisioningVMIpaddress=$(az vm list-ip-addresses --resource-group=ProctorVMRG --name=proctorVM --query "[].virtualMachine.network.publicIpAddresses[].ipAddress" -otsv)
    echo -e "IP Address of the provisioning VM is $provisioningVMIpaddress"
    bash ./send_msg.sh -n  -e $recipientEmail -c $chatConnectionString -q $chatMessageQueue -m "OpenHack credentials are here: http://$provisioningVMIpaddress:2018/teamfiles.zip with zip password $zipPassword"
fi

echo "############ END OF TEAM PROVISION ############"
