LOG8415: Final Project
======================

***Scaling Databases and Implementing Cloud Patterns***

**Author:** *Simon Tran - 1961278*

# Requirements

1. `final-project.pem`
2. In the AWS security group, add an inbound rule for port 1186

# Set right permissions for the `.pem` file

```bash
chmod 400 final-project.pem
```

# Installation

### Run the setup script for the standalone VM:

```bash
# Connect to the VM via SSH
./script.sh -c

# Install mysql-server
apt-get -y install mysql-server
```

Then follow the [instructions](https://www.linode.com/docs/guides/install-mysql-on-ubuntu-14-04/) to complete the MySQL installation.

Then install [Sakila](#sakila)

### Install MySQL Cluster on the master VM:

```bash
# Install the dependencies
./script.sh -d master

# Complete MySQL Cluster installation 
./script.sh -i master
```

### Install MySQL Cluster on the slave VMs:

```bash
# Install the dependencies
./script.sh -d slave1
./script.sh -d slave2
./script.sh -d slave3

# Complete MySQL Cluster installation
./script.sh -i slave1
./script.sh -i slave2
./script.sh -i slave3
```

### Execute the final setup script for the master VM:

```bash
./script.sh -f
```

Then, you need to secure the MySQL installation

```bash
# Connect to the master VM via SSH
./script.sh -c master

mysql_secure_installation
```

## Sakila

You need to install Sakila on the standalone and the master VM

```bash
./script.sh -s standalone
```

Connect to the VM and populate the DB

```bash
./script.sh -c standalone

mysql -u root -p

SOURCE sakila-db/sakila-schema.sql;
SOURCE sakila-db/sakila-data.sql;
exit;
```

Repeat the steps for the master VM
