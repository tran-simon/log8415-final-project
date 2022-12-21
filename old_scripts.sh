#!/bin/bash

set -e

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

set_vm_address() {
  vm_name=$1

  if [ -z "$vm_name" ]; then
    echo "Missing arguments"
    exit 1
  fi

  varname="${vm_name}_ip"
  vm_address="${!varname}"
}

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

copy_to_vm() {
  if [ -z "$pem_path" ] || [ -z "$username" ] || [ -z "$vm_address" ]; then
    echo "Missing arguments"
    exit 1
  fi

  scp -i "$pem_path" "$1" "$username"@"$vm_address":"$2"
}

install_mysql_cluster_dependencies() {
  copy_to_vm "resources/mysqlc.sh" "mysqlc.sh"
  run_on_vm "mkdir -p /opt/mysqlcluster/home && \
      cd /opt/mysqlcluster/home && \
      wget http://dev.mysql.com/get/Downloads/MySQL-Cluster-7.2/mysql-cluster-gpl-7.2.1-linux2.6-x86_64.tar.gz && \
      tar xvf mysql-cluster-gpl-7.2.1-linux2.6-x86_64.tar.gz && \
      ln -sf mysql-cluster-gpl-7.2.1-linux2.6-x86_64 mysqlc && \
      rm -rf mysql-cluster-gpl-7.2.1-linux2.6-x86_64.tar.gz && \
      mv /home/ubuntu/mysqlc.sh /etc/profile.d/mysqlc.sh
      "

  run_on_vm "echo '[[ -f \"/etc/profile.d/mysqlc.sh\" ]] && source /etc/profile.d/mysqlc.sh' >> /home/ubuntu/.profile"

  echo "2. Install libncurses5"
  run_on_vm "apt-get update && \
      apt-get -y install libncurses5 sysbench
      "
}

# https://stansantiago.wordpress.com/2012/01/04/installing-mysql-cluster-on-ec2/
install_mysql_cluster() {
  echo "Installing MySQL Cluster on $vm_name"

  if [ "$vm_name" = "master" ]; then
    echo "----- SQL/Mgmt Node specific steps -----"

    my_cnf="
[mysqld]
ndbcluster
datadir=/opt/mysqlcluster/deploy/mysqld_data
basedir=/opt/mysqlcluster/home/mysqlc
port=3306

[mysql_cluster]
ndb-connectstring=$master_ip_internal
"

    config_ini="
[ndb_mgmd]
hostname=$master_ip_internal
datadir=/opt/mysqlcluster/deploy/ndb_data
nodeid=1

[ndbd default]
noofreplicas=3
datadir=/opt/mysqlcluster/deploy/ndb_data

[ndbd]
hostname=$slave1_ip_internal
nodeid=3

[ndbd]
hostname=$slave2_ip_internal
nodeid=4

[ndbd]
hostname=$slave3_ip_internal
nodeid=5

[mysqld]
hostname=$master_ip_internal
nodeid=50"

    echo "1. Create the Deployment Directory and Setup Config Files"
    run_on_vm "mkdir -p /opt/mysqlcluster/deploy && \
      cd /opt/mysqlcluster/deploy && \
      mkdir -p conf && \
      mkdir -p mysqld_data && \
      mkdir -p ndb_data && \
      cd conf && \
      echo -e '$my_cnf' > my.cnf && \
      chmod 644 my.cnf && \
      echo -e '$config_ini' > config.ini
      "

    echo "2. Initialize the Database"
    run_on_vm "cd /opt/mysqlcluster/home/mysqlc && \
      scripts/mysql_install_db --no-defaults --datadir=/opt/mysqlcluster/deploy/mysqld_data
      "
    echo "3. Start management node"
    run_on_vm "mkdir -p /usr/local/mysql/mysql-cluster && \
      /opt/mysqlcluster/home/mysqlc/bin/ndb_mgmd -f /opt/mysqlcluster/deploy/conf/config.ini --initial --configdir=/opt/mysqlcluster/deploy/conf/
      "
  else
    echo "----- Slave specific steps -----"
    run_on_vm "mkdir -p /opt/mysqlcluster/deploy/ndb_data && \
      ndbd -c \"$master_ip_internal\":1186
      "
  fi
}

install_sakila() {
  run_on_vm "wget https://downloads.mysql.com/docs/sakila-db.tar.gz && \
    tar xvf sakila-db.tar.gz
    "
}

while getopts 'c:d:i:s:efmg' flag; do
  case "${flag}" in
  c)
    # Connect to the VM in ssh
    set_vm_address "${OPTARG}"
    run_on_vm ""
    ;;
  d)
    # Install dependencies on the VM
    set_vm_address "${OPTARG}"
    install_mysql_cluster_dependencies
    ;;
  e)
    # Exit mysqld on master
    set_vm_address master
    run_on_vm "killall mysqld"
    ;;
  i)
    # Install MySQL Cluster
    set_vm_address "${OPTARG}"
    install_mysql_cluster
    ;;
  f)
    # Final setup steps for master
    set_vm_address master
    run_on_vm "mysqld --defaults-file=/opt/mysqlcluster/deploy/conf/my.cnf --ndb-connectstring=localhost:1186 --user=root &"
    ;;
  m)
    # Run `ndb_mgm` on the master
    set_vm_address master
    run_on_vm "ndb_mgm"
    ;;
  s)
    # Install Sakila on the VM
    set_vm_address "${OPTARG}"
    install_sakila
    ;;
  *) ;;
  esac
done
