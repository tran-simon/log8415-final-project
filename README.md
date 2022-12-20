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

1. Install MySQL on the standalone VM
2. Install MySQL Cluster on the master VM:
```bash
./script.sh -i master
```
