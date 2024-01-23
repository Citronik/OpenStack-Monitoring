#!/bin/bash

MODEL_NAME="upgrade-test"
USER=$(whoami)
SCRIPT_BASE_PATH=$(pwd)
CHARMS_FILE="bundleKISprod-cephWEB.yaml"
MAAS_LOGIN="student"
JUJU_USER="test-student"
MAAS_API_KEY="$SCRIPT_BASE_PATH/maas-api-key"
MAAS_IP=$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
MAAS_PORT="5240"
MAAS_URL="http://$MAAS_IP:$MAAS_PORT/MAAS"
VAULT_INIT="false"
VAULT_GEN_KEY="false"
VAULT_KEY_NUM="5"
VAULT_KEY_THRESH="3"
CERT_EXPORT="false"

debug_print() {
	echo "[------------------------------------------------]"
	echo "Model name: $MODEL_NAME"
	echo "User: $USER"
	echo "Current path: $SCRIPT_BASE_PATH"
	echo "Charms file: $CHARMS_FILE"
	echo $MAAS_LOGIN
	echo $MAAS_API_KEY
	echo $MAAS_URL
	echo $VAULT_GEN_KEY
	echo $VAULT_KEY_NUM
	echo $VAULT_KEY_THRESH
	echo "[------------------------------------------------]"
}

print_help() {
	echo "      full-deploy.sh [CHARMS_FILE] [OPTIONS]"
	echo "[---------------------------------------------]"
	echo "	Script for deploying OpenStack charms on MAAS using Juju."
	echo "necessary arguments:"
	echo " "
	echo "		CHARMS_FILE				path to the openstack charms.yaml file"
	echo "[---------------------------------------------]"
	echo "optional arguments:"
	echo " "
	echo "	--print-default				print the default values for the attributes"
	echo "	--model-name <val>			name of the model to be created"
	echo "	--maas-login <val>			loggin to maas as a user"
	echo "	--maas-url <val>			maas url"
	echo "	--maas-api-key <val>		maas api key"
	echo "	--maas-api-file <val>		maas api key file"
	echo "	--vault-init				just initialize vault and skip other steps"
	echo "	--vault-key-num <val>		number of keys to be generated"
	echo "	--vault-key-thresh <val>	threshold for the keys"
	echo "	--vault-gen-key				generate new keys"
	echo "	--cert-export				export the root ca certificate"
	echo "	--help -h					print this help message"
	echo "	--version -v				print the version of this script"
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
	if [ "$#" -le 1 ]; then
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
	echo "Parsing attributes..."
	CHARMS_FILE=$1
	shift 1
	while [ $# -gt 0 ]; do
		case "$1" in
			--print-default)
				debug_print
				exit 0
				;;
			--model-name)
				MODEL_NAME="$2"
				shift 2
				;;
			--maas-login)
				MAAS_LOGIN="$2"
				shift 2
				;;
			--maas-url)
				MAAS_URL="$2"
				shift 2
				;;
			--maas-api-key)
				MAAS_API_KEY="$2"
				shift 2
				;;
			--vault-init)
				#initialize_vault $@
				VAULT_INIT="true"
				shift 1
				#exit 0
				;;
			--vault-key-num)
				VAULT_KEY_NUM="$2"
				shift 2
				;;
			--vault-key-thresh)
				VAULT_KEY_THRESH="$2"
				shift 2
				;;
			--vault-gen-key)
				VAULT_GEN_KEY="true"
				shift 1
				;;
			--cert-export)
				CERT_EXPORT="true"
				shift 1
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
	echo "Attribute parsing completed succesfully! :)"
}

login_To_Maas() {
    maas login $MAAS_LOGIN $MAAS_URL - < $MAAS_API_KEY
}

check_Vault_Dep() {
	if ! command -v vault &> /dev/null; then
		echo "Vault is not installed. Please install Vault before running this script."
		exit 1
	fi
	if $VAULT_KEY_THRESH -ge $VAULT_KEY_NUM; then
		echo "Threshold is bigger than the number of keys. Please change the threshold or the number of keys."
		exit 1
	fi

	# check if vault has enought keys

}

wait_for_vault() {
	STATE=$(juju status | grep vault/ | awk -F ' ' '{print $2}')
	STATUS=$(juju status | grep vault/ | awk -F ' ' '{print $3}')
	while [[ $STATE != "blocked" || $STATUS != "idle" ]]; do
		echo "Waiting for vault to be ready..."
		sleep 20
		STATE=$(juju status | grep vault/ | awk -F '	' '{print $2}')
		STATUS=$(juju status | grep vault/ | awk -F '	' '{print $3}')
	done
}

### Break into the functions
initialize_vault() {
	wait_for_vault
	VAULT_IP=$(juju status | grep vault/ | awk -F ' ' '{print $5}')
	VAULT_PORT=$(juju status | grep vault/ | awk -F ' ' '{print $6}' | awk -F '/' '{print $1}')
	VAULT_KEYS_FILE="$SCRIPT_BASE_PATH/vaultKeys.txt"
	VAULT_KEYS_FILE_BKP="$SCRIPT_BASE_PATH/vaultKeys.txt.bkp"
	VAULT_TOKEN_FILE="$SCRIPT_BASE_PATH/vaultToken.txt"
	echo "" > logs.txt
	keyArray=()
	#echo " " > $VAULT_TOKEN_FILE
	check_Vault_Dep
	echo "Initializing vault..."
	export VAULT_ADDR="http://$VAULT_IP:$VAULT_PORT"

	if [ $VAULT_GEN_KEY == "true" ]; then
		echo "Generating vault keys..." >> logs.txt
		echo "Generating vault keys..."
		echo " " > $VAULT_KEYS_FILE
		echo " " > $VAULT_KEYS_FILE_BKP

		vault operator init -key-shares=$VAULT_KEY_NUM -key-threshold=$VAULT_KEY_THRESH > $VAULT_KEYS_FILE
		cat $VAULT_KEYS_FILE >> logs.txt
		if [ $? -ne 0 ]; then
			echo "Generation failed! :("
			exit 1
		fi
		echo "Generation completed succesfully! :)"
	fi
	echo "[ Unsealing vault... ]" >> logs.txt
	for i in $(seq 1 $VAULT_KEY_THRESH); do
		echo "Unsealing vault key num: $i..."
		line=$(sed "${i}q;d" $VAULT_KEYS_FILE)
		keyArray[i]=$(echo $line | awk -F ' ' '{print $4}')
		vault operator unseal ${keyArray[i]} >> logs.txt
	done

	export VAULT_TOKEN=$(cat vaultKeys.txt | grep "Root Token" | awk -F ' ' '{print $4}') 
	echo "Vault token: $VAULT_TOKEN"
	vault token create -ttl=10m > $VAULT_TOKEN_FILE
	echo "$VAULT_TOKEN_FILE"
	token=$(cat $VAULT_TOKEN_FILE | grep "token " | awk -F ' ' '{print $2}')
	
	juju run-action --wait vault/leader authorize-charm token=$token >> logs.txt
	echo "---GENERATING ROOT CA---" >> logs.txt
	juju run-action --wait vault/leader generate-root-ca >> logs.txt
	
	### check if vault is ready
	echo "status"
	juju status | grep vault
}

deploy_The_Charms() {

	login_To_Maas $@
	maas $MAAS_LOGIN discoveries clear all=True
	echo "Deploying charms..."
	STATUS=$(juju models)
	#juju add-model $MODEL_NAME
	#juju grant $JUJU_USER admin $MODEL_NAME
	juju switch admin/upgrade-test
	juju deploy $SCRIPT_BASE_PATH/$CHARMS_FILE
	echo "Waiting for charms to be ready..."
	sleep 3600
}

cert_export() {
	ROOT_CA="/tmp/${MODEL_NAME}root-ca.crt"
	if [ -d ~/snap/openstackclients/common/ ]; then
		# When using the openstackclients confined snap the certificate has to be
		# placed in a location reachable by the clients in the snap.
		ROOT_CA="~/snap/openstackclients/common/${MODEL_NAME}root-ca.crt"
	fi
	echo "Exporting root ca certificate... to $ROOT_CA"
	juju run -m admin/${MODEL_NAME} --unit vault/leader 'leader-get root-ca' | tee $ROOT_CA >/dev/null 2>&1
}

echo "Starting OpenStack deployment..."

check_For_Other $@

check_For_Dependencies $@

#debug_print

parse_attributes $@

#debug_print

if [ "$VAULT_INIT" == "true" ]; then
	initialize_vault $@
	exit 0
fi

case "true" in
	$CERT_EXPORT)
		cert_export
		exit 0
		;;
	$VAULT_INIT)
		initialize_vault $@
		exit 0
		;;
esac

deploy_The_Charms $@

initialize_vault $@



echo "OpenStack deployment completed succesfully! :)"
exit 0