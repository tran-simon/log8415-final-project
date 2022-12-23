LOG8415: Final Project
======================

***Scaling Databases and Implementing Cloud Patterns***

**Author:** *Simon Tran - 1961278*

# Installation

1. Create 5 t2.micro EC2 instances (for standalone, master, slave1, slave2, slave3)
2. Create 1 t2.large instance for the proxy server
3. Add the IP addresses of all the VMs in the `.env` file.
   You may use this command to easily get all the IPs
    ```bash
    aws ec2 describe-instances --output table --query 'Reservations[].Instances[].[Tags[?Key==`Name`] | [0].Value, PublicIpAddress, PrivateIpAddress]'
    ```
4. Run the installation script
    ```bash
    ./install.sh
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
./scripts.sh proxy query random "SELECT * FROM actor;"
./scripts.sh proxy query customized "SHOW DATABASES;"

./scripts.sh proxy query random "SHOW VARIABLES WHERE Variable_name = 'ndb_nodeid';"
./scripts.sh proxy query customized "SHOW VARIABLES WHERE Variable_name = 'hostname';"
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
./scripts.sh master status sakila
```

## NDB Manage

```bash
./scripts.sh master manage
```
