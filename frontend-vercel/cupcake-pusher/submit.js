const { Kafka } = require('kafkajs');
const express = require('express');

const redpanda = new Kafka({
    clientId: 'store-app',
    brokers: ["co258dppom78tp54qp20.any.us-east-1.mpx.prd.cloud.redpanda.com:9092"],
    ssl: {},
    sasl: {
        mechanism: "scram-sha-256",
        username: "admin",
        password: "1234qwer"
    }
})

const producer = redpanda.producer()
const app = express();

app.use(express.json());

app.post('/submit', async function(req, res) {
    const { store, blueberry, strawberry } = req.body;

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