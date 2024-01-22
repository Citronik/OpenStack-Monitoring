#!/bin/bash

MODEL_NAME="test"
USER=$(whoami)
SCRIPT_BASE_PATH=$(pwd)
CHARMS_FILE="$SCRIPT_BASE_PATH/bundleKISprod-cephWEB.yaml"
MAAS_LOGIN="student"
MAAS_API_KEY="$SCRIPT_BASE_PATH/maas-api-key"
MAAS_URL="http://10.11.0.2:5240/MAAS"


debug_print() {
	echo $MODEL_NAME
	echo $USER
	echo $SCRIPT_BASE_PATH
	echo $CHARMS_FILE
	echo $MAAS_LOGIN
	echo $MAAS_API_KEY
	echo $MAAS_URL
}

print_help() {
	echo "      full-deploy.sh [CHARMS_FILE] [OPTIONS]"
	echo "[---------------------------------------------]"
	echo "necessary arguments:"
	echo "      CHARMS_FILE	        path to the openstack charms.yaml file"
	echo "[---------------------------------------------]"
	echo "optional arguments:"
	echo "      --model-name	    name of the model to be created"
	echo "      --maas-login	    loggin to maas as a user"
	echo "      --maas-url	        maas url"
	echo "      --maas-api-key	    maas api key"
	echo "      --help -h		    print this help message"
	echo "      --version -v	    print the version of this script"
	echo "[---------------------------------------------]"
}

check_For_Other() {
    if echo "$1" | grep -E -q '^-?-?h(elp)?$'; then
	    print_help
	    exit 0
    fi

    if echo "$1" | grep -E -q '^-?-?v(ersion)?$'; then
        echo "Full OpenStack deploy version 1.0"
        exit 0
    fi
}

check_For_Dependencies() {
	echo "Checking for dependencies..."
	if [ "$#" -ne 1 ]; then
		echo "Usage: $0 <charms.yaml>"
		exit 1
	fi
	if ! command -v juju &> /dev/null; then
		echo "Juju is not installed. Please install Juju before running this script."
		exit 1
	fi
	maas_status=$(maas status 2>&1 || true)
	if [[ $maas_status == *"command not found"* ]]; then
		echo "MAAS command not found. Please install MAAS before running this script."
		exit 1
	fi
	echo "Dependency check completed succesfully! :)"
}

parse_attributes() {
	while [ $# -gt 0 ]; do
		case "$2" in
			--maas-login)
				MAAS_LOGIN="$3"
				shift 2
				;;
			--maas-url)
				MAAS_URL="$3"
				shift 2
				;;
			--maas-api-key)
				MAAS_API_KEY="$3"
				shift 2
				;;
			--help|-h)
				print_help
				exit 0
				;;
			--version|-v)
				echo "Full OpenStack deploy version 1.0"
				exit 0
				;;
			*)
				echo "Unknown option: $1"
				exit 1
				;;
		esac
	done
}

login_To_Maas() {
    maas login $MAAS_LOGIN $MAAS_URL - < $MAAS_API_KEY
}

deploy_The_Charms() {
	maas $MAAS_LOGIN discoveries clear all=True
	juju add-model $MODEL_NAME
	juju grant $ admin $MODEL_NAME
	juju deploy $SCRIPT_BASE_PATH/bundleKISprod-cephWEB.yaml
}

echo "Starting OpenStack deployment..."

check_For_Other $@

check_For_Dependencies $@

debug_print

parse_attributes $@

debug_print
#login_To_Maas $@



echo "OpenStack deployment completed succesfully! :)"
exit 0