# Installation

```bash
./scripts.sh master dependencies
./scripts.sh master install

./scripts.sh master dependencies server
./scripts.sh master install server

./scripts.sh master start ndb

# For each slave
./scripts.sh slave1 dependencies
./scripts.sh slave1 install
./scripts.sh slave1 start ndb


# Start mysql. This command can take some time
./scripts.sh master start mysql


# Install Sakil
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
