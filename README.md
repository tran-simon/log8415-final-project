LOG8415: Final Project
======================

***Scaling Databases and Implementing Cloud Patterns***

**Author:** *Simon Tran - 1961278*

# Installation

1. Create 5 t2.micro EC2 instances (for standalone, master, slave1, slave2, slave3)
2. Create 1 t2.large instance for the proxy server
3. Add the IP addresses of all the VMs in the `.env` file.
4. Run the installation commands below

```bash
./scripts.sh master dependencies
./scripts.sh master install

./scripts.sh master dependencies server
./scripts.sh master install server

# For each slave
./scripts.sh slave1 dependencies
./scripts.sh slave1 install
./scripts.sh slave2 dependencies
./scripts.sh slave2 install
./scripts.sh slave3 dependencies
./scripts.sh slave3 install

# Start mysql. This command can take some time
./scripts.sh master start mysql

# Start ndb for the master then for each slave
./scripts.sh master start ndb
./scripts.sh slave1 start ndb
./scripts.sh slave2 start ndb
./scripts.sh slave3 start ndb


# Install Sakila
./scripts.sh standalone install sakila
./scripts.sh master install sakila

# Install sysbench
./scripts.sh standalone install sysbench
./scripts.sh master install sysbench
```

# Benchmark

```bash
./scripts.sh standalone start sysbench
./scripts.sh master start sysbench
```

# Proxy

```bash
./scripts.sh proxy dependencies
./scripts.sh proxy install

./scripts.sh proxy start
```

## Test some queries

```bash
./scripts.sh proxy query direct-hit "SHOW STATUS;"
./scripts.sh proxy query random "SELECT * FROM ACTOR;"
./scripts.sh proxy query customized "SHOW DATABASES;"

./scripts.sh proxy query random "SHOW VARIABLES WHERE Variable_name = 'ndb_nodeid';"
./scripts.sh proxy query customized "SHOW VARIABLES WHERE Variable_name = 'hostname'"
```

# Useful commands

```bash
# To connect to the VM via SSH
./scripts.sh master connect

# You may also use `connect` to run commands
./scripts.sh master connect "ps aux"

# To run SQL commands on the VM
./scripts.sh master sql "SHOW DATABASES;"
```

## Stop processes

```bash
./scripts.sh master stop ndb
./scripts.sh master stop mysql
```

## Status commands

```bash
./scripts.sh master status mysql
./scripts.sh master status cluster
./scripts.sh master status ndb
./scripts.sh master status sakil
```

## NDB Manage

```bash
./scripts.sh master manage
```
