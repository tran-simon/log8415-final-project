

```bash
./scripts.sh master dependencies
./scripts.sh master install

./scripts.sh master dependencies server
./scripts.sh master install server

./scripts.sh master start_ndb

# For each slave
./scripts.sh slave1 dependencies
./scripts.sh slave1 install
./scripts.sh slave1 start_ndb


# Start mysql. This command can take some time
./scripts.sh master start_mysql

```


```bash
./scripts.sh master connect
sudo mysql -u root -p
```
```mysql
SHOW ENGINE NDB STATUS \G
```

# Install Sakila

Do these operations for master and standalone

```bash
./scripts.sh master install_sakila
```

```bash
./scripts.sh master connect
sudo mysql -u root -p
```
```mysql
SOURCE sakila-db/sakila-schema.sql;
SOURCE sakila-db/sakila-data.sql;
    
# Confirm
USE sakila;
SHOW FULL TABLES;
```
