import re
import subprocess
import json
import logging

logging.basicConfig(level=logging.INFO)
### Set
devmode=False
JUJU_STATUS_COMMAND_JSON = 'juju status --format=json'
JUJU_STATUS_COMMAND_PLAIN = 'juju status'
LOKI_URL = 'http://10.254.0.5/loki/api/v1/push'

PROMTAIL_SCRIPT_PATH = "./promtail_install.sh"

# with open(PROMTAIL_SCRIPT_PATH, 'r') as file:
    # PROMTAIL_INSTALL_SCRIPT = file.read()

#PROMTAIL_INSTALL_SCRIPT = script

PROMTAIL_CONFIG_MAIN = """
server:
    http_listen_port: 9080
    grpc_listen_port: 0
    log_level: "info"

positions:
    filename: /tmp/positions.yaml

clients:
    - url: {LOKI_URL}
      tenant_id: OpenStack

scrape_configs:
"""
PROMTAIL_CONFIG_JOB = """
  - job_name: {SERVICE_NAME}-logs
    static_configs:
      - targets:
          - localhost
        labels:
          job: {SERVICE_NAME}
          __path__: {SERVICE_LOG_PATH}
"""

LOG_DIRECTORY_MAPPING = {
    'ceph-fs': '/var/log/ceph/',
    'ceph-mon': '/var/log/ceph/',
    'ceph-dashboard': '/var/log/ceph/',
    'ceph-osd': '/var/log/ceph/',
    'ceph-radosgw': '/var/log/ceph/',
    'cinder': '/var/log/cinder/',
    'cinder-ceph': '/var/log/cinder/',
    'cinder-mysql-router': '/var/log/mysql/',
    'designate': '/var/log/designate/',
    'designate-bind': '/var/log/designate/',
    'glance': '/var/log/glance/',
    'glance-mysql-router': '/var/log/mysql/',
    'heat': '/var/log/heat/',
    'keystone': '/var/log/keystone/',
    'keystone-mysql-router': '/var/log/mysql/',
    'manila': '/var/log/manila/',
    'manila-ganesha': '/var/log/manila/',
    'memcached': '/var/log/memcached/',
    'mysql-innodb-cluster': '/var/log/mysql/',
    'neutron-api': '/var/log/neutron/',
    'neutron-api-plugin-ovn': '/var/log/neutron/',
    'neutron-mysql-router': '/var/log/mysql/',
    'nova-cloud-controller': '/var/log/nova/',
    'nova-compute': '/var/log/nova/',
    'nova-mysql-router': '/var/log/mysql/',
    'ntp': '/var/log/chrony/',
    'ovn-chassis': '/var/log/ovn/',
    'openstack-dashboard': '/var/log/horizon/',
    'dashboard-mysql-router': '/var/log/mysql/',
    'ovn-central': '/var/log/ovn/',
    'placement': '/var/log/placement/',
    'placement-mysql-router': '/var/log/mysql/',
    'rabbitmq-server': '/var/log/rabbitmq/',
    'vault': '/var/log/vault/',
    'vault-mysql-router': '/var/log/mysql/',
}


if devmode:
    logging.basicConfig(level=logging.DEBUG)
    JUJU_STATUS_COMMAND_JSON = 'cat debugJujuStatus.json'
    JUJU_STATUS_COMMAND_PLAIN = 'cat debugJujuStatus.txt'

class JujuUnit():
    def __init__(self, unit, lxd, machineIP) -> None:
        self.unit = unit
        self.lxd = lxd
        self.machineIP = machineIP
        
    def appNameFromUnit(self) -> str:
        return self.unit.split('/')[0]
    
    def __str__(self) -> str:
        return f"Unit: {self.unit} - LXD: {self.lxd} - Machine IP: {self.machineIP}"
    
    def __json__(self):
        return {
            "name": self.appNameFromUnit(),
            "unit": self.unit,
            "lxd": self.lxd,
            "machineIP": self.machineIP
        }

class JujuMachine():
    def __init__(self, name, hostname=None, ipAddresses=None) -> None:
        self.name = name
        self.hostname = hostname
        self.ipAddresses = ipAddresses
        self.unit = []
        self.unitNumber = 0
        self.promtailInstalled = False
        self.promtailConfigTransferred = False
        self.promtailConfig = None

    def addUnit(self, appName: JujuUnit) -> None:
        self.unit.append(appName)
        self.unitNumber += 1
    
    def popUnit(self) -> str:
        if self.unitNumber > 0:
            self.unitNumber -= 1
            return self.unit.pop()
        else:
            return None
    
    def __str__(self) -> str:
        if self.unitNumber == 0:
            return f"{self.name} - {self.hostname} - {self.ipAddresses} - Apps: { self.unitNumber }"
        units_str = "\n".join([str(unit) for unit in self.unit])
        return f"-"*70 + f"\n{self.name} - {self.hostname} - {self.ipAddresses} - Apps: {self.unitNumber} \n[\n{units_str}\n]\n" + f"-"*70 
    
    def __json__(self):
        return {
            "machine": self.name,
            "hostname": self.hostname,
            "ipAddresses": self.ipAddresses,
            "unit": [unit.__json__() for unit in self.unit]
        }



def run_command(command):
    '''Function to run a shell command and return the output.'''
    result = subprocess.run(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    logging.info(f"Running Command: {command}")
    return result.stdout, result.stderr

def juju_cmnd(command) -> str:
    jujuResult, jujuError = run_command(command)
    if jujuError:
        logging.error(f"Error running juju status command: {jujuError}")
        return jujuError
    #jujuParsedResult = json.loads(jujuResult)
    logging.info(f"Juju Status retrieved [{len(jujuResult)}] bytes")
    return jujuResult

def parseMachineInfoFromJSON(parsedMachines, machine):
    server = JujuMachine(name=machine[0])
    server.hostname = machine[1]['hostname']
    server.ipAddresses = machine[1]['ip-addresses'][0]
    #print(f"{server}")
    logging.info(f"Parsing Machine: {server}")
    parsedMachines[server.ipAddresses]= server
    if 'containers' not in machine[1]:
        return
    for container in machine[1]['containers'].items():
        parseMachineInfoFromJSON(parsedMachines, container)
        
def parseJujuMachinesFromJSON(allMachines):
    print("-"*50)
    parsedMachines = {}
    for machine in allMachines:
        #print(machine)
        parseMachineInfoFromJSON(parsedMachines, machine)
    
    logging.info(f"Juju Machines parsed [{len(parsedMachines)}]")
    return parsedMachines

def parseAppInfoFromJSON(parsedApps, app):
    appObj = JujuUnit(name=app[0], status=app[1]['status']['current'], units=[])
    #TODO: Parse units
    logging.info(f"Parsing App: {appObj}")
    parsedApps.append(appObj)

def parseJujuAppsFromJSON(allApps):
    logging.info(f"Parsing Juju Apps [{len(allApps)}]")
    #print(f"{allApps}")
    parsedApps = []
    for app in allApps:
        parseAppInfoFromJSON(parsedApps, app)
    logging.info(f"Juju Apps parsed [{len(parsedApps)}]")
    return parsedApps

def parseJujuAppsFromStatus(status):
    parsedApps = []
    
    return parsedApps

def parseJujuAppsToMachinesFromStatus(status, machines):
    logging.info(f"Parsing Juju Apps to Machines...")
    #subStatus = status[status.find("Unit"):status.find("Machine")]
    #print(f"Substatus:\n {subStatus}")
    #pattern = re.compile(r"^(?P<unit_name>\S+)\s+.*?\s+(?P<machine>[^\s]+)\s+(?P<ip_address>\d+\.\d+\.\d+\.\d+)")
    pattern = re.compile(r"^(?P<unit_name>\S+)\s+.*?(?:(?P<machine>[^\s]+)\s+)?(?P<ip_address>\d+\.\d+\.\d+\.\d+)")

    isUnit = False
    unitBefore = None
    apps = []
    lines = 0
    for line in status.splitlines():
        # print(f"Line num: {lines}")
        lines += 1
        if line.startswith("Unit") and not isUnit:
            logging.debug(f"Unit line: {line}")
            isUnit = True
            continue
        if line.startswith("Machine") and isUnit:
            logging.debug(f"Unit finished: {line}")
            isUnit = False
            break
        if isUnit:            
            match = pattern.search(line.strip())
            if match:
                logging.debug(f"   mathched line: {line}")
                unit_name = match.group("unit_name")
                machine = match.group("machine") if match.group("machine") else "No machine"
                ip_address = match.group("ip_address")
                newUnit = JujuUnit(unit=unit_name, lxd=machine, machineIP=ip_address)
                if machine == "No machine":
                    machine = unitBefore.lxd
                logging.debug(f"      {newUnit}")
                machines[ip_address].addUnit(newUnit)
                apps.append(newUnit)
                unitBefore = newUnit

    logging.info(f"Juju [{len(apps)}] Apps parsed to Machines")

def preparePromtailConfig(machine: JujuMachine) -> str:
    logging.info(f"Preparing Promtail Config for Machine: {machine.name}")
    if len(machine.unit) == 0:
        logging.info(f"No Units found for Machine: {machine.name}")
        return None
    config = PROMTAIL_CONFIG_MAIN.format(LOKI_URL=LOKI_URL)
    logging.debug(f"Units {len(machine.unit)}")
    logging.debug(f"Units: {machine.unit}")
    for unit in machine.unit:
        appName = unit.appNameFromUnit()
        logging.debug(f"AppName: {appName}")
        if appName in LOG_DIRECTORY_MAPPING:
            logPath = LOG_DIRECTORY_MAPPING[appName]
            logging.debug(f"Log Path: {logPath}")
            if logPath in config:
                continue
            logPath = f"{logPath}*.log"
            config += PROMTAIL_CONFIG_JOB.format(SERVICE_NAME=appName, SERVICE_LOG_PATH=logPath)

    logging.info(f"Promtail Config prepared for Machine: {machine.name}")
    logging.debug(f"Promtail Config: {config}")
    return config
            
def installPromtail(machine: JujuMachine) -> bool:
    """ Install Promtail on a machine"""
    logging.info(f"Installing Promtail on Machine: {machine.name}")
    config_filename = "promtail-config.yml"
    remote_config_path = f"/etc/promtail/{config_filename}"
    remote_tmp_path = f"/home/ubuntu/{config_filename}"
    
    try:
        # Save the generated config to a local file temporarily
        with open(config_filename, 'w') as f:
            f.write(preparePromtailConfig(machine))

        # Copy installation script and config file to the remote machine
        subprocess.run(["juju", "scp", PROMTAIL_SCRIPT_PATH, f"{machine.name}:/tmp/promtail_install.sh"], check=True)

        logging.info(f"removing old promtail instance...")
        subprocess.run(["juju", "scp", 'promtail_remove.sh', f"{machine.name}:/tmp/promtail_remove.sh"], check=True)
        remove_command = f"sudo bash /tmp/promtail_remove.sh && rm /tmp/promtail_remove.sh"
        install_result = subprocess.run(["juju", "run", "--machine", machine.name, remove_command], capture_output=True, text=True)
        # Run the installation script via Juju
        install_command = f"sudo bash /tmp/promtail_install.sh && rm /tmp/promtail_install.sh"
        install_result = subprocess.run(["juju", "run", "--machine", machine.name, install_command], capture_output=True, text=True)
        install_config = subprocess.run(["juju", "scp", config_filename, f"{machine.name}:{remote_tmp_path}"], check=True)
        
        move_command = f"sudo mv {remote_tmp_path} {remote_config_path}"
        install_config = subprocess.run(["juju", "run", "--machine", machine.name, move_command], capture_output=True, text=True)

        with open(config_filename, 'r') as f:
            machine.promtailConfig = f.read()
        machine.promtailInstalled = True
        machine.promtailConfigTransferred = True

        if install_result.stderr:
            logging.error(f"Installation failed: {install_result.stderr} machine: {machine.name}")
            machine.promtailInstalled = False
            # return False
        if install_config.stderr:
            logging.error(f"Failed to copy config file: {install_config.stderr}")
            # return False

        logging.info(f"Promtail installed successfully on {machine.name}")
        return True
    except subprocess.CalledProcessError as e:
        logging.error(f"Failed to install Promtail on {machine.name}: {e}")
        return False
    
def checkPromtailPermisson(machine: JujuMachine):
    logging.info(f"Checking Promtail Permission on Machine: {machine.name}")
    try:
        for unit in machine.unit:
            command = f"sudo ls -dlha {LOG_DIRECTORY_MAPPING[unit.appNameFromUnit()]} "
            command += "| awk '{print $4}'"
            result = subprocess.run(["juju", "run", "--machine", machine.name, command], capture_output=True, text=True)
            
            if result.stderr:
                logging.error(f"Failed to check permission: {result.stderr}")
                return False
            
            group = result.stdout.strip()
            adjustPromtaiPermission = f"sudo usermod -aG {group} promtail"

            result = subprocess.run(["juju", "run", "--machine", machine.name, adjustPromtaiPermission], capture_output=True, text=True)

            if result.stderr:
                logging.error(f"Failed to adjust permission: {result.stderr}")
                return False
            
        command = "sudo systemctl restart promtail"
        result = subprocess.run(["juju", "run", "--machine", machine.name, command], capture_output=True, text=True)
        if result.stderr:
            logging.error(f"Failed to restart promtail: {result.stderr}")
            return False
        command = "sudo systemctl status promtail"
        result = subprocess.run(["juju", "run", "--machine", machine.name, command], capture_output=True, text=True)

        logging.info(f"Promtail status: {result.stdout}")
        return True

    except subprocess.CalledProcessError as e:
        logging.error(f"Failed to check Promtail status on {machine.name}: {e}")
        return False

if __name__ == "__main__":
    print("Running Promtail Juju Installer...")
    status = juju_cmnd(JUJU_STATUS_COMMAND_JSON)
    status = json.loads(status)
    parsedMachines = {}
    allMachines = status['machines'].items()
    allApps = status['applications'].items()

    jujuMachines = parseJujuMachinesFromJSON(allMachines)

    ###Parsing Apps using status command
    statusPlain = juju_cmnd(JUJU_STATUS_COMMAND_PLAIN)
    #logging.debug(f"Status Plain: {statusPlain}")
    parseJujuAppsToMachinesFromStatus(statusPlain, jujuMachines)
    # for machine in jujuMachines.values():
    #     print(f"{machine}")
    ### Prepare Config and install Promtail
    for machine in jujuMachines.values():
        promtailConfig = preparePromtailConfig(machine)
        if promtailConfig:
            # Save the generated config to a local file temporarily
            with open("promtail-config.yml", 'w') as f:
                f.write(promtailConfig)

            if installPromtail(machine):
                machine.promtailInstalled = True
                machine.promtailConfig = promtailConfig
                checkPromtailPermisson(machine)
        
        print("-"*50)

    
    print("Promtail Juju Installer Finished...")