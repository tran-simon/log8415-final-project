#!/bin/bash

set -e

# Read the environment variables in the `.env`. It contains the IP addresses of the VMs
set -a
source .env
set +a

username="ubuntu"
pem_path="final-project.pem"

vm_name="$1"
command="$2"
shift
shift
args=("$@")

if [ -z "$vm_name" ]; then
  echo "Missing arguments"
  exit 1
fi

varname="${vm_name}_ip"
vm_address="${!varname}"

# Run commands on the VM via SSH
run_on_vm() {
  if [ -z "$pem_path" ] || [ -z "$username" ] || [ -z "$vm_address" ]; then
    echo "Missing arguments"
    exit 1
  fi

  if [ -n "$1" ]; then
    ssh_command="set -e && $1"
  fi

  ssh -i "$pem_path" "$username"@"$vm_address" "$ssh_command"
}

# Run SQL queries on the VM via SSH
run_sql_on_vm() {
  run_on_vm "sudo mysql -u root -e \"$1\""
}

# Copy a file to the VM via SCP
copy_to_vm() {
  sftp -i "$pem_path" "$username"@"$vm_address" <<< "put \"$1\" \"$2\""
}

# The MySQL-Cluster `config.ini` configuration file for the master VM
config_ini="
[ndbd default]
# Options affecting ndbd processes on all data nodes:
NoOfReplicas=3	# Number of replicas

[ndb_mgmd]
# Management process options:
hostname=$master_ip_internal # Hostname of the manager
datadir=/var/lib/mysql-cluster 	# Directory for the log files

[ndbd]
hostname=$slave1_ip_internal # Hostname/IP of the first data node
NodeId=2			# Node ID for this data node
datadir=/usr/local/mysql/data	# Remote directory for the data files

[ndbd]
hostname=$slave2_ip_internal # Hostname/IP of the second data node
NodeId=3			# Node ID for this data node
datadir=/usr/local/mysql/data	# Remote directory for the data files

[ndbd]
hostname=$slave3_ip_internal # Hostname/IP of the second data node
NodeId=4			# Node ID for this data node
datadir=/usr/local/mysql/data	# Remote directory for the data files

[mysqld]
# SQL node options:
hostname=$master_ip_internal # In our case the MySQL server/client is on the same Droplet as the cluster manager
"

# The MySQL `my.cnf` configuration file for the slave VMs
my_cnf="
[mysql_cluster]
# Options for NDB Cluster processes:
ndb-connectstring=$master_ip_internal  # location of cluster manager
"

# The MySQL server `my.cnf` configuration file for the master VM
server_my_cnf="
!includedir /etc/mysql/conf.d/
!includedir /etc/mysql/mysql.conf.d/

[mysqld]
# Options for mysqld process:
ndbcluster                      # run NDB storage engine
bind-address=0.0.0.0
skip-grant-tables

[mysql_cluster]
# Options for NDB Cluster processes:
ndb-connectstring=$master_ip_internal  # location of management server
"

# Connect to the VM via SSH and optionally run commands
connect() {
  run_on_vm "$args"
}

# Run a SQL query on the VM
sql() {
  run_sql_on_vm "$args"
}

# Download the dependencies for the various nodes
dependencies() {
  case $args in
  server)
    # Install master server dependencies
    # This installs MySQL Cluster server as well as some other dependencies
    run_on_vm "cd ~ && \
      wget https://dev.mysql.com/get/Downloads/MySQL-Cluster-7.6/mysql-cluster_7.6.6-1ubuntu18.04_amd64.deb-bundle.tar && \
      mkdir -p install && \
      sudo tar --overwrite -xvf mysql-cluster_7.6.6-1ubuntu18.04_amd64.deb-bundle.tar -C install/ && \
      cd install && \
      sudo apt update && \
      sudo apt install -y libaio1 libmecab2 libncurses5 && \
      sudo dpkg -i mysql-common_7.6.6-1ubuntu18.04_amd64.deb && \
      sudo dpkg -i mysql-cluster-community-client_7.6.6-1ubuntu18.04_amd64.deb && \
      sudo dpkg -i mysql-client_7.6.6-1ubuntu18.04_amd64.deb && \
      sudo dpkg -i mysql-cluster-community-server_7.6.6-1ubuntu18.04_amd64.deb && \
      sudo dpkg -i mysql-server_7.6.6-1ubuntu18.04_amd64.deb
      "
    ;;
  *)
    if [ "$vm_name" = "master" ]; then
      # Install the master dependencies
      # This installs the MySQL Cluster Manager, sysbench and other dependencies
      run_on_vm "cd ~ && \
        sudo apt update && \
        sudo apt install -y libtinfo5 sysbench && \
        wget https://dev.mysql.com/get/Downloads/MySQL-Cluster-7.6/mysql-cluster-community-management-server_7.6.6-1ubuntu18.04_amd64.deb && \
        sudo dpkg -i mysql-cluster-community-management-server_7.6.6-1ubuntu18.04_amd64.deb && \
        sudo mkdir -p /var/lib/mysql-cluster
        "
    elif [ "$vm_name" = "standalone" ]; then
      run_on_vm "sudo apt update && sudo apt install -y mysql-server sysbench"
    elif [ "$vm_name" = "proxy" ]; then
      # Install the proxy dependencies
      # This installs nodejs and nmap
      run_on_vm "cd ~ && \
        curl -sL https://deb.nodesource.com/setup_16.x -o /tmp/nodesource_setup.sh && \
        sudo bash /tmp/nodesource_setup.sh
        "
      run_on_vm "sudo apt update && sudo apt install -y nodejs nmap"
    else
      # Install the slave dependencies
      # This installs the MySQL-Cluster data node
      run_on_vm "
        cd ~ && \
        wget https://dev.mysql.com/get/Downloads/MySQL-Cluster-7.6/mysql-cluster-community-data-node_7.6.6-1ubuntu18.04_amd64.deb && \
        sudo apt update && \
        sudo apt install -y libclass-methodmaker-perl && \
        sudo dpkg -i mysql-cluster-community-data-node_7.6.6-1ubuntu18.04_amd64.deb
        "
    fi
    ;;
  esac
}

# Configure the various nodes
install() {
  case $args in
  server)
    # Set the configuration files for the MySQL Server
    run_on_vm "
      echo -e '$server_my_cnf' | sudo tee /etc/mysql/my.cnf && \
      sudo chmod 644 /etc/mysql/my.cnf && \
      sudo pkill -f mysql
      "
    ;;
  sakila)
    # Download the Sakila DB and add it to our MySQL db
    run_on_vm "wget https://downloads.mysql.com/docs/sakila-db.tar.gz && \
    sudo tar --overwrite -xvf sakila-db.tar.gz
    "
    run_sql_on_vm "SOURCE sakila-db/sakila-schema.sql;"
    run_sql_on_vm "SOURCE sakila-db/sakila-data.sql;"
    ;;
  sysbench)
    # Create the sysbench test database and add some rows
    run_sql_on_vm "CREATE DATABASE IF NOT EXISTS dbtest;"
    run_on_vm "sudo sysbench --mysql-socket=\"/var/run/mysqld/mysqld.sock\" --table-size=1000000 --mysql-db=dbtest --mysql-user=root --mysql-password=\"\" /usr/share/sysbench/oltp_read_only.lua prepare"
    ;;
  *)
    if [ "$vm_name" = "master" ]; then
      # Set the configuration file for MySQL Cluster Manager
      run_on_vm "
        echo -e '$config_ini' | sudo tee /var/lib/mysql-cluster/config.ini
        "
    elif [ "$vm_name" = "proxy" ]; then
      # Copy the proxy app files and install the package dependencies
      run_on_vm "rm -rf app final-project.pem && mkdir -p app"
      copy_to_vm "./proxy/index.js" "app/index.js"
      copy_to_vm "./proxy/package.json" "app/package.json"
      copy_to_vm "./proxy/package-lock.json" "app/package-lock.json"
      copy_to_vm "./.env" ".env"
      copy_to_vm "./final-project.pem" "final-project.pem"
      run_on_vm "cd app && npm install"
    else
      # Set the configuration file for the MySQL Data node
      run_on_vm "
        echo -e '$my_cnf' | sudo tee /etc/my.cnf && \
        sudo mkdir -p /usr/local/mysql/data
        "
    fi
    ;;
  esac
}

# Start various programs on the nodes
start() {
  case $args in
  ndb)
    if [ "$vm_name" = "master" ]; then
      # Start the NDB Cluster Management Server Daemon (used on the master node)
      run_on_vm "sudo /usr/sbin/ndb_mgmd -f /var/lib/mysql-cluster/config.ini"
    else
      # Start NDB (used on slave nodes)
      run_on_vm "sudo /usr/sbin/ndbd"
    fi
    ;;
  mysql)
    # Restart MySQL (used on the master node)
    run_on_vm "sudo systemctl restart mysql"
    ;;
  sysbench)
    # Run sysbench
    run_on_vm "sudo sysbench --mysql-socket=\"/var/run/mysqld/mysqld.sock\" --table-size=1000000 --num-threads=6 --max-time=60 --max-requests=0 --mysql-db=dbtest --mysql-user=root --mysql-password=\"\" /usr/share/sysbench/oltp_read_only.lua run"
    ;;
  *)
    if [ "$vm_name" = "proxy" ]; then
      # Restart the proxy app
      stop
      run_on_vm "cd app && npm start"
    fi
    ;;
  esac
}

# Stop various programs on the nodes
stop() {
  case $args in
  ndb)
    if [ "$vm_name" = "master" ]; then
      # Stop the NDB CLuster Management Server Daemon (used on the master node)
      run_on_vm "sudo pkill -f ndb_mgmd"
    else
      # Stop NDB (used on slave nodes)
      run_on_vm "sudo pkill -f ndbd"
    fi
    ;;
  mysql)
    # Stop MySQL (used on the master node)
    run_on_vm "sudo pkill -f mysql"
    ;;
  *)
    if [ "$vm_name" = "proxy" ]; then
      # Stop the proxy app
      curl -s -X POST "${vm_address}:3000/stop" || true
    fi
    ;;
  esac
}

# Get the status of various programms on the nodes
status() {
  case $args in
  mysql)
    run_on_vm "sudo systemctl status mysql"
    ;;
  cluster)
    run_sql_on_vm "SHOW ENGINE NDB STATUS \G"
    ;;
  ndb)
    run_on_vm "/usr/bin/ndb_mgm -e show"
    ;;
  sakila)
    run_sql_on_vm "USE sakila;
      SHOW FULL TABLES;
      "
    ;;
  esac
}

# Run ndb_mgm (used on the master node)
manage() {
  run_on_vm "/usr/bin/ndb_mgm"
}

# Send a SQL query to the proxy app
query() {
  url="${vm_address}:3000/${args[0]}"
  query="${args[@]:1}"

  curl -X POST -H "Content-Type: text/plain" -d "$query" "$url"
}

eval "$command"
