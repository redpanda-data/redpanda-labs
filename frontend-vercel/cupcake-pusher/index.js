const express = require('express');
const {Kafka} = require("kafkajs")

let { inventory } = require('./mapview.js');

const app = express();

const redpanda = new Kafka({
  clientId: 'store-app',
  brokers: [process.env.SERVERLESSBROKER],
  ssl: {},
  sasl: {
      mechanism: "scram-sha-256",
      username: process.env.RPUSER,
      password: process.env.RPPWD
  }
})

const producer = redpanda.producer()

app.use(express.json());

app.post('/submit', async function(req, res) {
  const { store, blueberry, strawberry } = req.body;
  console.log('Sending message:', { store, blueberry, strawberry });
  
  await producer.connect();
  await producer.send({
      topic: 'inv-count',
      messages: [
          { value: JSON.stringify({ store, blueberry, strawberry }) },
      ],
  });
  await producer.disconnect();

  res.json({ status: 'success' });
});

app.post('/clean-inventory', function(req, res) {
  inventory = {};
  res.json({ status: 'success' });
});

app.get('/', function(req, res) {
  res.sendFile(__dirname + '/index.html');
});

app.get('/input', function(req, res) {
  res.sendFile(__dirname + '/input.html');
});

app.get('/input.js', function(req, res) {
  res.sendFile(__dirname + '/input.js');
});

app.listen(3000, function() {
  console.log('App listening on port 3000!');
});