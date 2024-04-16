#!/bin/bash

MODEL_NAME="upgrade-test"
USER=$(whoami)
SCRIPT_BASE_PATH=$(pwd)
CHARMS_FILE="${SCRIPT_BASE_PATH}/bundleKISprod-cephWEB.yaml"
MAAS_LOGIN="student"
JUJU_USER="test-student"
JUJU_MODEL_USER="admin"
MAAS_API_KEY="$SCRIPT_BASE_PATH/maas-api-key"
MAAS_IP=$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
MAAS_PORT="5240"
MAAS_URL="http://$MAAS_IP:$MAAS_PORT/MAAS"
VAULT_KEY_NUM="5"
VAULT_KEY_THRESH="3"
NUMBER_COMMANDS=0
VAULT_INIT="false"
VAULT_GEN_KEY="false"
CERT_COPY="false"
CERT_EXPORT="false"
FULL_DEPLOY="false"
INIT_OPENSTACK="false"


ROOT_CA="/tmp/${MODEL_NAME}root-ca.crt"

debug_print() {
	echo "[------------------------------------------------]"
	echo "Model name: $MODEL_NAME"
	echo "User: $USER"
	echo "Current path: $SCRIPT_BASE_PATH"
	echo "Charms file: $CHARMS_FILE"
	echo "Maas login: $MAAS_LOGIN"
	echo "Maas api-key file: $MAAS_API_KEY"
	echo "Maas url: $MAAS_URL"
	echo "Generate vault keys: $VAULT_GEN_KEY"
	echo "Number of Vault key: $VAULT_KEY_NUM"
	echo "Threshold for Vault keys: $VAULT_KEY_THRESH"
	echo "[------------------------------------------------]"
}

# print_help() {
# 	echo "      ./full-deploy.sh [OPTIONS]"
# 	echo "[---------------------------------------------]"
# 	echo "	Script for deploying OpenStack charms on MAAS using Juju."
# 	#echo "necessary arguments:"
# 	echo " "
# 	#echo "		CHARMS_FILE				path to the openstack charms.yaml file"
# 	#echo "[---------------------------------------------]"
# 	echo "OPTIONS:"
# 	echo " "
# 	echo "	--print-default					print the default values for the attributes"
# 	#echo "	--full-deploy					deploy the charms and initialize vault"
# 	echo "	--bundle-path <val>				path to the openstack charms.yaml file"
# 	echo "	--model-name <val>				name of the model to perform the actions"
# 	echo "	--maas-login <val>				loggin to maas as a user"
# 	echo "	--maas-url <val>				maas url"
# 	echo "	--maas-api-key <val>			maas api key"
# 	echo "	--maas-api-file <val>			maas api key file"
# 	echo "	--vault-init					just initialize vault and skip other steps"
# 	echo "	--vault-key-num <val>			number of keys to be generated"
# 	echo "	--vault-key-thresh <val>		threshold for the keys"
# 	echo "	--vault-gen-key					generate new keys"
# 	echo "	--cert-copy						copy the root ca certificate from vault"
# 	echo "	--cert-export					export the root ca certificate to openstack"
# 	echo "	--init-openstack				initialize openstack"
# 	echo "	--destroy-model <val>			destroy the model"
# 	echo "	--delete-model-resources		delete all the deployed applications and machines"
# 	echo "	--help -h						print this help message"
# 	echo "	--version -v					print the version of this script"
# 	echo "[---------------------------------------------]"
# }

print_help() {
    printf "      ./full-deploy.sh [OPTIONS]\n"
    printf "[-----------------------------------------------------------]\n"
    printf "    Script for deploying OpenStack charms on MAAS using Juju.\n\n"
    printf "OPTIONS:\n\n"
    printf "    %-30s %s\n" "--print-default" "print the default values for the attributes"
    printf "    %-30s %s\n" "--bundle-path <val>" "path to the openstack charms.yaml file"
    printf "    %-30s %s\n" "--model-name <val>" "name of the model to perform the actions"
    printf "    %-30s %s\n" "--maas-login <val>" "log in to MAAS as a user"
    printf "    %-30s %s\n" "--maas-url <val>" "MAAS URL"
    printf "    %-30s %s\n" "--maas-api-key <val>" "MAAS API key"
    printf "    %-30s %s\n" "--maas-api-file <val>" "MAAS API key file"
    printf "    %-30s %s\n" "--vault-init" "just initialize vault and skip other steps"
    printf "    %-30s %s\n" "--vault-key-num <val>" "number of keys to be generated"
    printf "    %-30s %s\n" "--vault-key-thresh <val>" "threshold for the keys"
    printf "    %-30s %s\n" "--vault-gen-key" "generate new keys"
    printf "    %-30s %s\n" "--cert-copy" "copy the root CA certificate from vault"
    printf "    %-30s %s\n" "--cert-export" "export the root CA certificate to OpenStack"
    printf "    %-30s %s\n" "--init-openstack" "initialize OpenStack"
    printf "    %-30s %s\n" "--destroy-model <val>" "destroy the model"
    printf "    %-30s %s\n" "--delete-model-resources" "delete all the deployed applications and machines"
    printf "    %-30s %s\n" "--version -v" "print the version of this script"
    printf "    %-30s %s\n" "--help -h" "print this help message"
    printf "[-----------------------------------------------------------]\n"
}

check_Command_Success() {
	if [ $# -lt 2 ]; then
		echo "Missing arguments! :("
		return 1
	fi
	command="$1"
	expected_Output="$2"
	
	output=$(eval "$command")
	if echo "$output" | grep -q "$expected_Output"; then
		return 0
	else
		return 1
	fi
}

request_Approval() {
	echo "$1"
	#echo "Do you want to continue? [y/n]"
	read -r response
	if [ "$response" != "y" ]; then
		echo "Exiting the script..."
		exit 0
	fi
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
	#if [ "$#" -le 1 ]; then
	#	echo "Usage: $0 <charms.yaml>"
	#	exit 1
	#fi
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
	while [ $# -gt 0 ]; do
		echo "Attribute: $1"
		case "$1" in
			--bundle-path)
				CHARMS_FILE="$2"
				VAULT_GEN_KEY="true"
				FULL_DEPLOY="true"
				shift 2
				;;
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
				NUMBER_COMMANDS=$((NUMBER_COMMANDS+1))
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
			--cert-copy)
				CERT_COPY="true"
				NUMBER_COMMANDS=$((NUMBER_COMMANDS+1))
				shift 1
				;;
			--cert-export)
				CERT_EXPORT="true"
				NUMBER_COMMANDS=$((NUMBER_COMMANDS+1))
				shift 1
				;;
			--init-openstack)
				INIT_OPENSTACK="true"
				NUMBER_COMMANDS=$((NUMBER_COMMANDS+1))
				shift 1
				;;
			--destroy-model)
				shift 1
				destroy_Model $@
				exit 0
				;;
			--delete-model-resources)
				delete_Model_resources
				exit 0
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
	echo "Logging to MAAS..."
    maas login $MAAS_LOGIN $MAAS_URL - < $MAAS_API_KEY
	maas $MAAS_LOGIN discoveries clear all=True
}

check_Vault_Dep() {
	if ! command -v vault &> /dev/null; then
		echo "Vault is not installed. Please install Vault before running this script."
		exit 1
	fi
	if [ $VAULT_KEY_THRESH -ge $VAULT_KEY_NUM ]; then
		echo "Threshold is bigger than the number of keys. Please change the threshold or the number of keys."
		exit 1
	fi

	# check if vault has enought keys

}

wait_For_Resource() {
	STATE_CMND=$1
	STATUS_CMND=$2
	STATE=$(eval $STATE_CMND)
	STATUS=$(eval $STATUS_CMND)
	excepted_state=$3
	excepted_status=$4
	# echo "State: $STATE == $excepted_state Status: $STATUS == $excepted_status"
	echo -n "Waiting for resource to be ready."
	while [[ $STATE != $excepted_state || $STATUS != $excepted_status ]]; do
		echo -n "."
		sleep 8
		STATE=$(eval $STATE_CMND)
		STATUS=$(eval $STATUS_CMND)
		#echo "State: $STATE Status: $STATUS"
	done
	echo ""
	sleep 60
	echo "Resource is ready! :)"
}

wait_for_Message() {
	#echo $2
	MESSAGE_CMD=$1
	while ! eval "$MESSAGE_CMD"; do
		echo -n "."
		sleep 15
	done
	printf "DONE! :) \n"
}

wait_for_vault() {
	printf "Waiting for vault to be ready..."
	#wait_For_Resource "juju status | grep vault/ | awk '{print \$2}'" "juju status | grep vault/ | awk '{print \$3}'" "blocked" "idle"
	#### Vault needs to be initialized
	wait_for_Message "juju status vault | grep vault/ | grep -q 'Vault needs to be initialized'"
	# printf "Waiting for nova-compute to be ready..."
	# wait_For_Resource "juju status nova-compute | grep nova-compute/ | awk '{print \$2}'" "juju status nova-compute | grep nova-compute/ | awk '{print \$3}'" "active" "idle"
	# # wait for nova-cloud-controller
	# printf "Waiting for nova-cloud-controller to be ready..."
	# wait_For_Resource "juju status nova-cloud-controller | grep nova-cloud-controller/ | awk '{print \$2}'" "juju status nova-cloud-controller | grep nova-cloud-controller/ | awk '{print \$3}'" "active" "idle"
	# # wait for neutron-api
	# printf "Waiting for neutron-api to be ready..."
	# wait_For_Resource "juju status neutron-api | grep neutron-api/ | awk '{print \$2}'" "juju status neutron-api | grep neutron-api/ | awk '{print \$3}'" "active" "idle"
	# # wait for keystone
	# printf "Waiting for keystone to be ready..."
	# wait_For_Resource "juju status keystone | grep keystone/ | awk '{print \$2}'" "juju status keystone | grep keystone/ | awk '{print \$3}'" "active" "idle"

	return 0
}

### Break into the functions 
initialize_vault() {
	wait_for_vault 
	sleep 60
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
	juju status vault
}

deploy_The_Charms() {
	echo "Deploying charms..."
	#STATUS=$(juju models --format json)
	CURRENT_MODEL=$(juju models --format json | jq -r '."current-model"')
	echo "OpenStack will be deployed to: $CURRENT_MODEL"
	#juju switch admin/upgrade-test
	juju deploy $CHARMS_FILE
	echo "Waiting for charms to be ready..."
}

find_root_ca_dir() {
	if [ -d ~/snap/openstackclients/common/ ]; then
		# When using the openstackclients confined snap the certificate has to be
		# placed in a location reachable by the clients in the snap.
		ROOT_CA="/home/${USER}/snap/openstackclients/common/${MODEL_NAME}root-ca.crt"
	fi
	echo "Root ca certificate will be copied to: $ROOT_CA"
}

cert_Copy() {
	#ROOT_CA="/tmp/${MODEL_NAME}root-ca.crt"
	wait_For_Resource "juju status keystone | grep keystone/ | awk '{print \$2}'" "juju status keystone | grep keystone/ | awk '{print \$3}'" "active" "idle"
	find_root_ca_dir
	echo "Exporting root ca certificate... to $ROOT_CA"
	juju run -m ${MODEL_NAME} --unit vault/leader 'leader-get root-ca' | tee $ROOT_CA >/dev/null 2>&1
	echo "Root ca certificate copied succesfully! :)"
}

cert_Export() {
	echo "Exporting root ca certificate..."
	KEYSTONE_IP=$(juju run -m ${MODEL_NAME} --unit keystone/leader -- 'network-get --bind-address public')
	PASSWORD=$(juju run -m ${MODEL_NAME} --unit keystone/leader 'leader-get admin_passwd')

	find_root_ca_dir $@
	#echo "Exporting root ca certificate... to $ROOT_CA"

	echo "Password: ${PASSWORD}"

	export OS_REGION_NAME=RegionOne
	export OS_AUTH_VERSION=3
	export OS_CACERT=${ROOT_CA}
	export OS_AUTH_URL=https://${KEYSTONE_IP}:5000/v3
	export OS_PROJECT_DOMAIN_NAME=admin_domain
	export OS_AUTH_PROTOCOL=https
	export OS_USERNAME=admin
	export OS_AUTH_TYPE=password
	export OS_USER_DOMAIN_NAME=admin_domain
	export OS_PROJECT_NAME=admin
	export OS_PASSWORD=${PASSWORD}
	export OS_IDENTITY_API_VERSION=3

	#export OS_REGION_NAME OS_AUTH_VERSION OS_CACERT OS_AUTH_URL OS_PROJECT_DOMAIN_NAME OS_AUTH_PROTOCOL OS_USERNAME OS_AUTH_TYPE OS_USER_DOMAIN_NAME OS_PROJECT_NAME OS_PASSWORD OS_IDENTITY_API_VERSION

	#echo "--- Testing exports to initialize OpenStack CLI Client ---"
	#echo "--- Printing endpoints of OpenStack ---"
	openstack endpoint list --interface admin
	return 0
}

print_Endpoints() {
	echo "--- Testing exports to initialize OpenStack CLI Client ---"
	echo "--- Printing endpoints of OpenStack ---"
	openstack endpoint list --interface admin
}

check_Switch_Model() {
	if check_Command_Success "juju models --format json | jq -r '.\"current-model\"'" "${MODEL_NAME}"; then
		echo "Model already in use: $MODEL_NAME"
	else
		echo "Switching to model: $MODEL_NAME"
		juju switch $MODEL_NAME
	fi
}

create_Model() {
	echo "Creating model..."
	juju add-model $MODEL_NAME
	juju grant $JUJU_USER admin $MODEL_NAME

	check_Switch_Model $@
}

## Fully deploy the OpenStack
execute_Full_Deploy() {
	echo "Executing full deploy..."
	create_Model $@
	deploy_The_Charms $@
	initialize_vault $@
	
	cert_Copy $@
	cert_Export $@
	init_Openstack $@
	print_Endpoints $@
	echo "Full deploy completed succesfully! :)"
}

init_Openstack() {
	echo "Initializing OpenStack..."

	juju config openstack-dashboard default-domain="admin_domain"
	juju config rabbitmq-server cluster-partition-handling="autoheal"

	openstack image create --public --container-format bare \
	   --disk-format qcow2 --file ~/images/jammy-amd64.img \
	   jammy-amd64

	#openstack flavor create --ram 8192 --disk 50 --vcpus 10 test
	openstack flavor create --ram 1024 --disk 10 --vcpus 1 test

	#openstack network create --external --share \
	#   --provider-network-type flat --provider-physical-network physnet1 \
	#   ext-net-153

	#openstack subnet create --network ext-net-153 \
	#  --allocation-pool start=158.193.153.2,end=158.193.153.254 \
	#  --dns-nameserver 158.193.152.4 --gateway 158.193.153.1 \
	#  --subnet-range 158.193.153.0/24 EXT153

	openstack network create --external --share \
	   --provider-network-type flat --provider-physical-network physnet2 \
	   ext-net-154

	openstack subnet create --network ext-net-154 \
	  --allocation-pool start=158.193.154.20,end=158.193.154.220 \
	  --dns-nameserver 158.193.152.4 --gateway 158.193.154.1 \
	  --subnet-range 158.193.154.0/24 EXT154

	openstack keypair create --public-key /home/student/.ssh/openstack_ssh_key.pub --private-key /home/student/.ssh/openstack_ssh_key.key mykey

	openstack server create --image jammy-amd64 --flavor test \
	   --key-name mykey --network ext-net-154 \
	    test-instance

	#update compute quotas
	openstack quota set --cores -1 --class default
	openstack quota set --instances -1 --class default
	openstack quota set --ram -1 --class default
	openstack quota set --volumes -1 --class default
	openstack quota set --gigabytes -1 --class default


	#env | grep OS_PASSWORD | awk -F '=' '{print $2}'
	openstack endpoint list --interface admin
}

destroy_Model() {
	MODEL_NAME=$1
	#check_Switch_Model $@
	request_Approval "Do you want to really destroy the $MODEL_NAME? [y/n]"
	echo "Destroying model...: $MODEL_NAME"
	juju destroy-model $MODEL_NAME --no-wait -y --force
}

delete_Model_resources() {
	echo "Deleting model resources..."
	deployed_applications=$(juju status --format=json | jq -r '.applications | keys[]')
	deployed_machines=$(juju status --format=json | jq -r '.machines | keys[]')
	echo " ---------------- Deployed machines ---------------- "
	echo "$deployed_machines"
	sleep 3
	echo " -------------- Deployed applications -------------- "
	echo "$deployed_applications"

	request_Approval "Do you want to remove all the deployed applications and machines? [y/n]"

	for app in $deployed_applications; do
		juju remove-application $app
	done
	for machine in $deployed_machines; do
		juju remove-machine $machine
	done
}

final_evaluation_of_the_script() {
	echo "Final evaluation of the script..."
	login_To_Maas $@
	if [ $FULL_DEPLOY == "true" ]; then
		execute_Full_Deploy $@
	else
		while [ $NUMBER_COMMANDS -gt 0 ]; do
			case "true" in
				$VAULT_INIT)
					initialize_vault $@
					VAULT_INIT="false"
					#exit 0
					;;
				$CERT_COPY)
					cert_Copy
					CERT_COPY="false"
					#exit 0
					;;
				$CERT_EXPORT)
					cert_Export
					CERT_EXPORT="false"
					#exit 0
					;;
				$INIT_OPENSTACK)
					init_Openstack
					INIT_OPENSTACK="false"
					#exit 0
					;;
			esac
			NUMBER_COMMANDS=$((NUMBER_COMMANDS-1))
		done
	fi
}
###################################################################################
echo "Starting OpenStack deployment..."

# 1. Check for help and version
check_For_Other $@

# 2. Check for dependencies(maas and juju)
check_For_Dependencies $@

#debug_print

# 3. Parse the attributes
parse_attributes $@

#debug_print

# 4. Deploy the charms
final_evaluation_of_the_script $@

echo "OpenStack deployment completed succesfully! :)"
#exit 0
###################################################################################