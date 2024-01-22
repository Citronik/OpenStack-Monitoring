#!/bin/bash

MODEL_NAME="test"
SCRIPT_BASE_PATH="/home/student-test"
HELP_VARIOATIONS="^-?-?h(elp)?$"
CHARMS_FILE="/home/$MAAS_LOGIN/bundleKISprod-cephWEB.yaml"
MAAS_LOGIN="student"
MAAS_API_KEY="/home/$MAAS_LOGIN/maas-api-key"
MAAS_URL="http://10.11.0.2:5240/MAAS"


print_help() {
	echo "      full-deploy.sh [MODEL_NAME] [CHARMS_FILE] [OPTIONS]"
    echo "[---------------------------------------------]"
    echo "necessary arguments:"
	echo "      MODEL_NAME	        name for the model where openstack will be deployed"
	echo "      CHARMS_FILE	        path to the openstack charms.yaml file"
    echo "[---------------------------------------------]"
    echo "optional arguments:"
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

login_To_Maas() {
    maas login $MAAS_LOGIN $MAAS_URL - < /home/student-test/maas-api-key
}
check_For_Dependencies() {
	if ! command -v juju &> /dev/null; then
		echo "Juju is not installed. Please install Juju before running this script."
		exit 1
	fi

	# Check if MAAS is available
	maas_status=$(maas status 2>&1 || true)
	if [[ $maas_status == *"command not found"* ]]; then
		echo "MAAS command not found. Please install MAAS before running this script."
		exit 1
	fi

    if [ "$#" -ne 1 ]; then
        echo "Usage: $0 <MODEL_NAME>"
        exit 1
    fi


	# Check if charms.yaml file is provided as an argument
	if [ "$#" -ne 2 ]; then
		echo "Usage: $0 <charms.yaml>"
		exit 1
	fi
}

deploy_The_Charms() {
	maas $MAAS_LOGIN discoveries clear all=True


	juju add-model $MODEL_NAME
	juju grant test-student admin $MODEL_NAME
	juju deploy $SCRIPT_BASE_PATH/bundleKISprod-cephWEB.yaml
}
check_For_Other $@

check_For_Dependencies $@

echo "OpenStack deployment completed succesfully! :)"
exit 0