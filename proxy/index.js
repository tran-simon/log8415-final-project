'use strict';

import express from 'express';
import mysql from 'mysql';
import dotenv from 'dotenv';
import util from 'util';
import tunnel from 'tunnel-ssh'
import fs from 'fs'
import * as child_process from 'child_process';

const exec = util.promisify(child_process.exec);

// Load the environment variables. Should contain the IP addresses
dotenv.config({
  path: "../.env"
});

const app = express();
app.use(express.text());

const privateKey = fs.readFileSync('../final-project.pem')

const ips = {
  master: process.env.master_ip,
  slave1: process.env.slave1_ip,
  slave2: process.env.slave2_ip,
  slave3: process.env.slave3_ip
};

/**
 * Create a SSH tunnel from the master node to the `vmName` node
 * @param vmName The name of the VM to create the tunnel to. Can be one of `master`, `slave1`, `slave2`, `slave3`
 */
const getTunnel = (vmName) => {
  return tunnel({
    username: 'ubuntu',
    privateKey,
    password: '',
    host: ips[vmName],
    port: 22,
    dstHost: ips.master,
    dstPort: 3306,
    keepAlive: true
  })
}

/**
 * Create a sql connection using the SSH tunnel
 */
const getConnection = () => {
  return mysql.createConnection({
    host: 'localhost',
    port: 3306,
    user: 'root',
    password: '',
    database: 'sakila',
  });
}

/**
 * Send a SQL query to the `vmName` node
 * @param vmName The name of the VM to query, `slave1`, `slave2`, `slave3`
 * @param req Express request object
 * @param res Express response object
 */
const query = (vmName, req, res) => {
  const query = req.body;
  console.info(`Querying "${vmName}" with query:`, query)

  try {
    const tun = getTunnel(vmName);
    const connection = getConnection();

    connection.query(query, (err, results) => {
      if (err) {
        console.error(err);
        res.status(500).send(err.message);
        tun.close();
        return;
      }
      res.status(200).send(
        `Success: ${JSON.stringify(results)}`
      );
      tun.close();
    });
  } catch (err) {
    console.error(err)
    res.status(500).send(err.message)
  }
};

/* Routes */

// The direct-hit route. It can take an optional query parameter to choose the VM to query. Defaults to master.
app.post('/direct-hit', (req, res) => {
  const vmName = req.query.destination || 'master'
  query(vmName, req, res);
});

// The random route. It will query a random slave node
app.post('/random', (req, res) => {
  const vmNames = Object.keys(ips).slice(1);
  const vmName = vmNames[Math.floor(Math.random() * vmNames.length)];

  query(vmName, req, res);
});

// The customized route. It will query the node with the lowest ping.
app.post('/customized', (req, res) => {

  /**
   * Ping the `vmName` node and returns the latency
   * @param vmName The name of the VM to query, `slave1`, `slave2`, `slave3`
   * @return The latency in seconds
   */
  const ping = async (vmName) => {
    const {stdout, stderr} = await exec(`nmap -T5 -sn ${ips[vmName]}`);
    if (stderr) {
      console.error(stderr);
      return Promise.reject();
    }

    const matches = stdout.match(/Host is up \((.*)s latency\)./);

    if (!matches || matches.length < 2) {
      console.error(stdout);
      return Promise.reject();
    }

    return +matches[1]
  };

  const pingPromises = Object.keys(ips).map((vmName) => ({
    vmName,
    latency: ping(vmName)
  }));

  Promise.all(pingPromises).then((latencies) => {
    let minValue;
    for (let {latency, vmName} of latencies) {
      if (!minValue) {
        minValue = {latency, vmName};
        continue;
      }

      if (latency < minValue.latency) {
        minValue = {latency, vmName};
      }
    }

    console.info(`Smallest ping is ${minValue.vmName} with ${minValue.latency}s`)

    query(minValue.vmName, req, res);
  }).catch((e) => {
    console.error("Failed to ping servers:", e)
  });
});

app.listen(3000, () => {
  console.info("app listening on port 3000");
});
