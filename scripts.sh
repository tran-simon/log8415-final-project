#!/bin/bash

username="ubuntu"
pem_path="final-project.pem"

standalone_ip="3.91.252.24"
master_ip="44.211.78.92"
slave1_ip="3.92.133.161"
slave2_ip="44.201.184.43"
slave3_ip="44.202.253.40"
master_ip_internal="ip-172-31-80-128.ec2.internal"
slave1_ip_internal="ip-172-31-91-242.ec2.internal"
slave2_ip_internal="ip-172-31-89-76.ec2.internal"
slave3_ip_internal="ip-172-31-95-222.ec2.internal"

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
    command="set -e && $1"
  fi

  ssh -i "$pem_path" "$username"@"$vm_address" "$command"
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

[mysql_cluster]
# Options for NDB Cluster processes:
ndb-connectstring=$master_ip_internal  # location of management server
"

connect() {
  run_on_vm ""
}

dependencies() {
  if [ "$vm_name" = "master" ]; then
    if [ "$args" != "server" ]; then
      run_on_vm "cd ~ && \
        sudo apt update && \
        sudo apt install -y libtinfo5 sysbench && \
        wget https://dev.mysql.com/get/Downloads/MySQL-Cluster-7.6/mysql-cluster-community-management-server_7.6.6-1ubuntu18.04_amd64.deb && \
        sudo dpkg -i mysql-cluster-community-management-server_7.6.6-1ubuntu18.04_amd64.deb && \
        sudo mkdir -p /var/lib/mysql-cluster
        "
    else
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
    fi
  else
    run_on_vm "
      cd ~ && \
      wget https://dev.mysql.com/get/Downloads/MySQL-Cluster-7.6/mysql-cluster-community-data-node_7.6.6-1ubuntu18.04_amd64.deb && \
      sudo apt update && \
      sudo apt install -y libclass-methodmaker-perl && \
      sudo dpkg -i mysql-cluster-community-data-node_7.6.6-1ubuntu18.04_amd64.deb
      "
  fi
}

install() {
  if [ "$vm_name" = "master" ]; then
    if [ "$args" != "server" ]; then
      run_on_vm "
        echo -e '$config_ini' | sudo tee /var/lib/mysql-cluster/config.ini
        "
    else
      run_on_vm "
        echo -e '$server_my_cnf' | sudo tee /etc/mysql/my.cnf && \
        sudo chmod 644 /etc/mysql/my.cnf && \
        sudo pkill -f mysql
        "
    fi
  else
    run_on_vm "
      echo -e '$my_cnf' | sudo tee /etc/my.cnf && \
      sudo mkdir -p /usr/local/mysql/data
      "
  fi
}

install_sakila() {
  run_on_vm "wget https://downloads.mysql.com/docs/sakila-db.tar.gz && \
    tar xvf sakila-db.tar.gz
    "
}

install_sysbench() {
  run_on_vm "sudo sysbench --mysql-socket=\"/var/run/mysqld/mysqld.sock\" --table-size=1000000 --mysql-db=sakila --mysql-user=root --mysql-password=\"\" /usr/share/sysbench/oltp_read_only.lua prepare"
}

sysbench() {
  run_on_vm "sudo sysbench --mysql-socket=\"/var/run/mysqld/mysqld.sock\" --table-size=1000000 --num-threads=6 --max-time=60 --max-requests=0 --mysql-db=sakila --mysql-user=root --mysql-password=\"\" /usr/share/sysbench/oltp_read_only.lua run"
}

start_ndb() {
  if [ "$vm_name" = "master" ]; then
    run_on_vm "sudo /usr/sbin/ndb_mgmd -f /var/lib/mysql-cluster/config.ini"
  else
    run_on_vm "sudo /usr/sbin/ndbd"
  fi
}

stop_ndb() {
  if [ "$vm_name" = "master" ]; then
    run_on_vm "sudo pkill -f ndb_mgmd"
  else
    run_on_vm "sudo pkill -f ndbd"
  fi
}

start_mysql() {
  run_on_vm "sudo systemctl start mysql"
}

stop_mysql() {
  run_on_vm "sudo pkill -f mysql"
}

status() {
  run_on_vm "sudo systemctl status mysql"
}

manage() {
  run_on_vm "/usr/bin/ndb_mgm"
}

eval "$command"
