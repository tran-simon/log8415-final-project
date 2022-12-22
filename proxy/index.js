'use strict';

import express from 'express';
import mysql from 'mysql';
import dotenv from 'dotenv';
import util from 'util';
import * as child_process from 'child_process';

const exec = util.promisify(child_process.exec);

dotenv.config({
  path: "../.env"
});

const app = express();

app.use(express.text());

const ips = {
  master: process.env.master_ip,
  slave1: process.env.slave1_ip,
  slave2: process.env.slave2_ip,
  slave3: process.env.slave3_ip
};

const connections = {};
const tunnels = {};

Object.keys(ips).map((key, i) => {
  const dstPort = 4000 + i;
  const ip = ips[key];
  tunnels[key] = child_process.spawn('ssh', [
    '-oStrictHostKeyChecking=no',
    '-i', '../final-project.pem',
    '-L', `${dstPort}:${ip}:3306`,
    `ubuntu@${ip}`
  ]);

  connections[key] = mysql.createConnection({
    host: `127.0.0.1`,
    port: dstPort,
    user: 'root',
    password: '',
    database: 'sakila'
  });
});

process.on('exit', () => {
  for (let key of Object.keys(ips)) {
    tunnels[key].kill();
    connections[key].destroy();
  }
});

const query = (connectionKey, req, res) => {
  const query = req.body;
  connections[connectionKey].query(query, (err, results) => {
    if (err) {
      console.error(err);
      res.status(500).send(err.message);
      return;
    }

    res.status(200).send(
      `Success: ${JSON.stringify(results)}`
    );
  });
};

app.post('/direct-hit', (req, res) => {
  const connectionKey = req.query.destination || 'master'
  query(connectionKey, req, res);
});

app.post('/random', (req, res) => {
  const connectionKeys = Object.keys(connections).slice(1);
  const connectionKey = connectionKeys[Math.floor(Math.random() * connectionKeys.length)];

  query(connectionKey, req, res);
});

app.post('/customized', (req, res) => {
  const ping = async (key) => {
    const {stdout, stderr} = await exec(`nmap -T5 -sn ${ips[key]}`);
    if (stderr) {
      console.error(stderr);
      return Promise.reject();
    }

    const matches = stdout.match(/Host is up \((.*)s latency\)./);

    if (!matches || matches.length < 2) {
      console.error(stdout);
      return Promise.reject();
    }

    return {latency: +matches[1], key};
  };

  const pingPromises = Object.keys(connections).map((key) => ping(key));

  Promise.all(pingPromises).then((latencies) => {
    let minValue;
    for (let {latency, key} of latencies) {
      if (!minValue) {
        minValue = {latency, key};
        continue;
      }

      if (latency < minValue.latency) {
        minValue = {latency, key};
      }
    }

    query(minValue.key, req, res);
  }).catch((e)=>{
    console.error("Failed to ping servers:", e)
  });
});

app.listen(3000, () => {
  console.log("app listening on port 3000");
});
