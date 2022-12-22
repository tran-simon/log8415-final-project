#!/bin/bash

set -e

set -a
source .env
set +a

username="ubuntu"
pem_path="final-project.pem"

# https://www.digitalocean.com/community/tutorials/how-to-create-a-multi-node-mysql-cluster-on-ubuntu-18-04#prerequisites

vm_name="$1"
command="$2"
shift
shift
args="$@"

if [ -z "$vm_name" ]; then
  echo "Missing arguments"
  exit 1
fi

varname="${vm_name}_ip"
vm_address="${!varname}"

run_on_vm() {
  if [ -z "$pem_path" ] || [ -z "$username" ] || [ -z "$vm_address" ]; then
    echo "Missing arguments"
    exit 1
  fi

  if [ ! -z "$1" ]; then
    ssh_command="set -e && $1"
  fi

  ssh -i "$pem_path" "$username"@"$vm_address" "$ssh_command"
}

run_sql_on_vm() {
  run_on_vm "sudo mysql -u root -e \"$1\""
}

copy_to_vm() {
  scp -i "$pem_path" "$1" "$username"@"$vm_address":"$2"
}

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
bind-address=0.0.0.0
skip-grant-tables
"

my_cnf="
[mysql_cluster]
# Options for NDB Cluster processes:
ndb-connectstring=$master_ip_internal  # location of cluster manager
"

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

connect() {
  run_on_vm "$args"
}

sql() {
  run_sql_on_vm "$args"
}

dependencies() {
  case $args in
  server)
    # Server deps
    run_on_vm "cd ~ && \
      wget https://dev.mysql.com/get/Downloads/MySQL-Cluster-7.6/mysql-cluster_7.6.6-1ubuntu18.04_amd64.deb-bundle.tar && \
      mkdir -p install && \
      tar -xvf mysql-cluster_7.6.6-1ubuntu18.04_amd64.deb-bundle.tar -C install/ && \
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
      run_on_vm "cd ~ && \
        sudo apt update && \
        sudo apt install -y libtinfo5 sysbench && \
        wget https://dev.mysql.com/get/Downloads/MySQL-Cluster-7.6/mysql-cluster-community-management-server_7.6.6-1ubuntu18.04_amd64.deb && \
        sudo dpkg -i mysql-cluster-community-management-server_7.6.6-1ubuntu18.04_amd64.deb && \
        sudo mkdir -p /var/lib/mysql-cluster
        "
    elif [ "$vm_name" = "proxy" ]; then
      run_on_vm "sudo apt update && sudo apt install -y nodejs npm"
    else
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

install() {
  case $args in
  server)
    run_on_vm "
      echo -e '$server_my_cnf' | sudo tee /etc/mysql/my.cnf && \
      sudo chmod 644 /etc/mysql/my.cnf && \
      sudo pkill -f mysql
      "
    ;;
  sakila)
    run_on_vm "wget https://downloads.mysql.com/docs/sakila-db.tar.gz && \
    tar xvf sakila-db.tar.gz
    "
    run_sql_on_vm "SOURCE sakila-db/sakila-schema.sql;"
    run_sql_on_vm "SOURCE sakila-db/sakila-data.sql;"
    ;;
  sysbench)
    run_sql_on_vm "CREATE DATABASE IF NOT EXISTS dbtest;"
    run_on_vm "sudo sysbench --mysql-socket=\"/var/run/mysqld/mysqld.sock\" --table-size=1000000 --mysql-db=dbtest --mysql-user=root --mysql-password=\"\" /usr/share/sysbench/oltp_read_only.lua prepare"
    ;;
  *)
    if [ "$vm_name" = "master" ]; then
      run_on_vm "
        echo -e '$config_ini' | sudo tee /var/lib/mysql-cluster/config.ini
        "
    elif [ "$vm_name" = "proxy" ]; then
      run_on_vm "rm -rf app final-project.pem && mkdir -p app"
      copy_to_vm "./proxy/index.js" "app/index.js"
      copy_to_vm "./proxy/package.json" "app/package.json"
      copy_to_vm "./proxy/package-lock.json" "app/package-lock.json"
      copy_to_vm "./.env" ".env"
      copy_to_vm "./final-project.pem" "final-project.pem"
      run_on_vm "cd app && npm install"
    else
      run_on_vm "
        echo -e '$my_cnf' | sudo tee /etc/my.cnf && \
        sudo mkdir -p /usr/local/mysql/data
        "
    fi
    ;;
  esac
}

start() {
  case $args in
  ndb)
    if [ "$vm_name" = "master" ]; then
      run_on_vm "sudo /usr/sbin/ndb_mgmd -f /var/lib/mysql-cluster/config.ini"
    else
      run_on_vm "sudo /usr/sbin/ndbd"
    fi
    ;;
  mysql)
    run_on_vm "sudo systemctl restart mysql"
    ;;
  sysbench)
    run_on_vm "sudo sysbench --mysql-socket=\"/var/run/mysqld/mysqld.sock\" --table-size=1000000 --num-threads=6 --max-time=60 --max-requests=0 --mysql-db=dbtest --mysql-user=root --mysql-password=\"\" /usr/share/sysbench/oltp_read_only.lua run"
    ;;
  *)
    if [ "$vm_name" = "proxy" ]; then
      run_on_vm "cd app && npm start &"
    fi
    ;;
  esac
}

stop() {
  case $args in
  ndb)
    if [ "$vm_name" = "master" ]; then
      run_on_vm "sudo pkill -f ndb_mgmd"
    else
      run_on_vm "sudo pkill -f ndbd"
    fi
    ;;
  mysql)
    run_on_vm "sudo pkill -f mysql"
    ;;
  * )
    if [ "$vm_name" = "proxy" ]; then
      run_on_vm "sudo pkill -f nodemon"
    fi
  esac
}

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

manage() {
  run_on_vm "/usr/bin/ndb_mgm"
}

eval "$command"
