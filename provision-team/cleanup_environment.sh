#!/bin/bash

usage() { echo "Usage: cleanup_environment.sh -t <teamName> -p <password>" 1>&2; exit 1; }

while getopts ":t:p:" arg; do
    case "${arg}" in
        t)
            teamName=${OPTARG}
        ;;
        p)
            password=${OPTARG}
        ;;
    esac
done

if [[ -z "$teamName" ]]; then
    echo "Enter the teamName to use for filepath"
    read teamName
fi
if [[ -z "$password" ]]; then
    echo "Enter the password to encrypt the zip file"
    read password
fi
# create a www directory
if [[ ! -d "/home/zhaw/www" ]]; then
    mkdir -p /home/zhaw/www
fi

# Copy the kubeconfig file
kubeconfiglocation="/home/azureuser/team_env/$teamName/kubeconfig-$teamName"
cp /root/.kube/config /home/zhaw/www/kubeconfig
chmod 644 /home/zhaw/www/kubeconfig
cp /root/.kube/config $kubeconfiglocation
echo "Copied the kubeconfig file to $kubeconfiglocation"

kvstore set $teamName kubeconfig $kubeconfiglocation
kvstore set $teamName zippassword $password

# Setup files to serve via nginx
cp /home/zhaw/team_env/./kvstore/${teamName} /home/zhaw/www/ohteamvalues
zip -e --password ${password} /home/zhaw/www/teamfiles.zip /home/zhaw/www/kubeconfig /home/zhaw/www/ohteamvalues
echo "Zipped /home/zhaw/www/teamfiles.zip with password $password"
cp /home/zhaw/openhack-devops-proctor/provision-team/nginx/index.html /home/zhaw/www/index.html

cp -R /home/zhaw/www/* /home/nginx/contents

# Set proper ownership for the regular user after script completes
# chown -R azureuser:azureuser /home/azureuser
