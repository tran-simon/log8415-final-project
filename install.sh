#!/bin/bash

echo "Configuring standalone..."
./scripts.sh standalone dependencies

echo "Configuring master..."
./scripts.sh master dependencies
./scripts.sh master install

echo "Configuring the mysql server on the master..."
./scripts.sh master dependencies server
./scripts.sh master install server

echo "Configuring each slave..."
./scripts.sh slave1 dependencies
./scripts.sh slave1 install
./scripts.sh slave2 dependencies
./scripts.sh slave2 install
./scripts.sh slave3 dependencies
./scripts.sh slave3 install

echo "Start mysql. This command can take some time"
./scripts.sh master start mysql

echo "Start ndb for the master then for each slave..."
./scripts.sh master start ndb
./scripts.sh slave1 start ndb
./scripts.sh slave2 start ndb
./scripts.sh slave3 start ndb


echo "Install Sakila..."
./scripts.sh standalone install sakila
./scripts.sh master install sakila

echo "Install sysbench..."
./scripts.sh standalone install sysbench
./scripts.sh master install sysbench
