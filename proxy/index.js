'use strict';

import express from 'express';
import mysql from 'mysql';
import dotenv from 'dotenv';
import util from 'util';
import fs from 'fs'
import * as child_process from 'child_process';

const exec = util.promisify(child_process.exec);

// Load the environment variables. Should contain the IP addresses
dotenv.config({
  path: "../.env"
});

const app = express();
app.use(express.text());

const vmNames = [
  'master',
  'slave1',
  'slave2',
  'slave3'
]

// Create a map of VMName:IP
const ips = vmNames.reduce((ips, vmName) => {
  ips[vmName] = process.env[`${vmName}_ip`]
  return ips
}, {})


// Create a SSH tunnel for each VM
const tunnels = vmNames.reduce((tunnels, vmName, i) => {
  const port = 4000 + i;

  const tunnel = child_process.spawn('ssh', [
    '-oStrictHostKeyChecking=no',
    '-tt',
    '-i', '../final-project.pem',
    '-L', `${port}:${ips.master}:3306`,
    `ubuntu@${ips[vmName]}`
  ]);

  tunnel.stderr.setEncoding('utf8')
  tunnel.stderr.on('data', (v) => {
    console.log('SSH Tunnel error:', v)
  })

  tunnels[vmName] = tunnel

  return tunnels
}, {})

const cleanTunnels = ()=>{
  console.info("Cleaning tunnels...")
  for (const tunnel of Object.values(tunnels)) {
    tunnel.kill()
  }
}

process.on('exit', cleanTunnels)

/**
 * Create a sql connection using the SSH tunnel
 */
const getConnection = (vmName) => {
  const port = 4000 + vmNames.indexOf(vmName)

  return mysql.createConnection({
    host: 'localhost',
    port,
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
    const connection = getConnection(vmName);

    connection.query(query, (err, results) => {
      if (err) {
        console.error(err);
        res.status(500).send(err.message);
        return;
      }
      res.status(200).send(
        `Success: ${JSON.stringify(results)}`
      );
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
  const slaveVmNames = vmNames.slice(1);
  const vmName = slaveVmNames[Math.floor(Math.random() * slaveVmNames.length)];

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

  const pingPromises = vmNames.map(async (vmName) => ({
    vmName,
    latency: await ping(vmName)
  }));

  Promise.all(pingPromises).then((latencies) => {
    let minValue;
    for (const {latency, vmName} of latencies) {
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

app.post('/stop', (_req, res) => {
  console.info('Exiting...')
  res.sendStatus(200)
  process.exit(0);
})

app.listen(3000, () => {
  console.info("app listening on port 3000");
});
