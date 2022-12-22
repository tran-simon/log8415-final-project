'use strict';

import express from 'express';
import mysql from 'mysql';
import dotenv from 'dotenv';
import {spawn} from 'child_process';

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
  tunnels[key] = spawn('ssh', [
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

app.post('/direct-hit', (req, res) => {
  const query = req.body;
  connections.master.query(query, (err, results) => {
    if (err) {
      console.error(err);
      res.status(500).send(err.message);
      return;
    }

    res.status(200).send(
      `Success: ${JSON.stringify(results)}`
    );
  });
});

app.listen(3000, () => {
  console.log("app listening on port 3000");
});
