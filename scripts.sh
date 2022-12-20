#!/bin/bash

set -e

username="ubuntu"
pem_path="final-project.pem"

standalone_ip="44.211.224.215"
master_ip="52.91.93.213"
slave1_ip="54.162.216.13"
slave2_ip="3.88.221.192"
slave3_ip="3.85.44.53"

set_vm_address() {
  vm_name=$1

  if [ -z "$vm_name" ]; then
    echo "Missing arguments"
    exit 1
  fi

  varname="${vm_name}_ip"
  vm_address="${!varname}"
}

connect() {
  if [ -z "$pem_path" ] || [ -z "$username" ] || [ -z "$vm_address" ]; then
    echo "Missing arguments"
    exit 1
  fi

  if [ ! -z "$1" ]; then
    command="sudo bash -c \"set -e && $1\""
  fi

  ssh -i "$pem_path" "$username"@"$vm_address" "$command"
}

copy_to_vm() {
  if [ -z "$pem_path" ] || [ -z "$username" ] || [ -z "$vm_address" ]; then
    echo "Missing arguments"
    exit 1
  fi

  scp -i "$pem_path" "$1" "$username"@"$vm_address":"$2"
}

# https://stansantiago.wordpress.com/2012/01/04/installing-mysql-cluster-on-ec2/
function install_mysql_cluster() {
  echo "Installing MySQL Cluster on $vm_name"

  echo "1. Common Steps for all Nodes"
  copy_to_vm "resources/mysqlc.sh" "mysqlc.sh"
  connect "mkdir -p /opt/mysqlcluster/home && \
      cd /opt/mysqlcluster/home && \
      wget http://dev.mysql.com/get/Downloads/MySQL-Cluster-7.2/mysql-cluster-gpl-7.2.1-linux2.6-x86_64.tar.gz && \
      tar xvf mysql-cluster-gpl-7.2.1-linux2.6-x86_64.tar.gz && \
      ln -sf mysql-cluster-gpl-7.2.1-linux2.6-x86_64 mysqlc && \
      rm -rf mysql-cluster-gpl-7.2.1-linux2.6-x86_64.tar.gz && \
      mv /home/ubuntu/mysqlc.sh /etc/profile.d/mysqlc.sh
      "

  echo "2. Install libncurses5"
  connect "apt-get update && \
      apt-get -y install libncurses5
      "

  if [ "$vm_name" = "master" ]; then
    echo "----- SQL/Mgmt Node specific steps -----"

    my_cfg="
[mysqld]
ndbcluster
datadir=/opt/mysqlcluster/deploy/mysqld_data
basedir=/opt/mysqlcluster/home/mysqlc
port=3306"

    config_ini="
[ndb_mgmd]
hostname=ip-172-31-17-89.ec2.internal
datadir=/opt/mysqlcluster/deploy/ndb_data
nodeid=1

[ndbd default]
noofreplicas=3
datadir=/opt/mysqlcluster/deploy/ndb_data

[ndbd]
hostname=$slave1_ip
nodeid=3

[ndbd]
hostname=$slave2_ip
nodeid=4

[ndbd]
hostname=$slave3_ip
nodeid=5

[mysqld]
nodeid=50"

    echo "1. Create the Deployment Directory and Setup Config Files"
    connect "mkdir -p /opt/mysqlcluster/deploy && \
      cd /opt/mysqlcluster/deploy && \
      mkdir -p conf && \
      mkdir -p mysqld_data && \
      mkdir -p ndb_data && \
      cd conf && \
      echo -e '$my_cfg' > my.cfg && \
      echo -e '$config_ini' > config.ini
      "

    echo "2. Initialize the Database"
    connect "cd /opt/mysqlcluster/home/mysqlc && \
      scripts/mysql_install_db --no-defaults --datadir=/opt/mysqlcluster/deploy/mysqld_data
      "
    echo "3. Start management node"
    connect "source /etc/profile.d/mysqlc.sh && \
      mkdir -p /usr/local/mysql/mysql-cluster && \
      /opt/mysqlcluster/home/mysqlc/bin/ndb_mgmd -f /opt/mysqlcluster/deploy/conf/config.ini --initial --configdir=/opt/mysqlcluster/deploy/conf/ --ndb-nodeid=1
      "
  fi

}

while getopts 'c:i:' flag; do
  case "${flag}" in
  c)
    # Connect to the VM in ssh
    set_vm_address "${OPTARG}"
    connect ""
    ;;
  i)
    # Install MySQL Cluster
    set_vm_address "${OPTARG}"
    install_mysql_cluster
    ;;
  *) ;;
  esac
done
