LOG8415: Final Project
======================

***Scaling Databases and Implementing Cloud Patterns***

**Author:** *Simon Tran - 1961278*

# Requirements

1. `final-project.pem`
2. In the AWS security group, add an inbound rule for port 1186, 3306 and for the range of ports  30000 to 65535

# Set right permissions for the `.pem` file

```bash
chmod 400 final-project.pem
```

# Installation

### Run the setup script for the standalone VM:

```bash
# Connect to the VM via SSH
./old_scripts.sh -c

# Install mysql-server
apt-get -y install mysql-server
```

Then follow the [instructions](https://www.linode.com/docs/guides/install-mysql-on-ubuntu-14-04/) to complete the MySQL installation.

Then install [Sakila](#sakila)

### Install MySQL Cluster on the master VM:

```bash
# Install the dependencies
./old_scripts.sh -d master

# Complete MySQL Cluster installation 
./old_scripts.sh -i master
```

### Install MySQL Cluster on the slave VMs:

```bash
# Install the dependencies
./old_scripts.sh -d slave1
./old_scripts.sh -d slave2
./old_scripts.sh -d slave3

# Complete MySQL Cluster installation
./old_scripts.sh -i slave1
./old_scripts.sh -i slave2
./old_scripts.sh -i slave3
```

### Execute the final setup script for the master VM:

```bash
./old_scripts.sh -f
```

You may stop mysqld using
```bash
mysqladmin -u root -p shutdown
```


Then, you need to secure the MySQL installation

```bash
# Connect to the master VM via SSH
./old_scripts.sh -c master

mysql_secure_installation
```

## Sakila

You need to install Sakila on the standalone and the master VM

```bash
./old_scripts.sh -s standalone
```

Connect to the VM and populate the DB

```bash
./old_scripts.sh -c standalone

mysql -u root -p

SOURCE sakila-db/sakila-schema.sql;
SOURCE sakila-db/sakila-data.sql;
exit;
```

Repeat the steps for the master VM

## Benchmark
https://www.jamescoyle.net/how-to/1131-benchmark-mysql-server-performance-with-sysbench

```mysql
create database dbtest;
```

```bash
sysbench --mysql-socket="/tmp/mysql.sock" --table-size=1000000 --mysql-db=dbtest --mysql-user=root --mysql-password="" /usr/share/sysbench/oltp_read_only.lua prepare
```

```mysql
use dbtest;
show tables;
SELECT COUNT(*) FROM sbtest1;
```

```bash
sysbench --mysql-socket="/tmp/mysql.sock" --table-size=1000000 --num-threads=6 --max-time=60 --max-requests=0 --mysql-db=dbtest --mysql-user=root --mysql-password="" /usr/share/sysbench/oltp_read_only.lua run
```

```mysql
drop database dbtest;
```
