
const {Kafka} = require("kafkajs")
const WebSocket = require('ws');
const fs = require('fs');
const csv = require('csv-parser');


const wss = new WebSocket.Server({ port: 8080 });

let inventory = {}; // This object will store our inventory data
let storeLocations = {}; // This object will store our store locations data


// Read the CSV file and store the data in storeLocations
fs.createReadStream('store_nyc.csv')
  .pipe(csv())
  .on('data', (row) => {
    storeLocations[row.storeid] = { lat: parseFloat(row.lat), lng: parseFloat(row.lng), store: row.storename };
  })
  .on('end', () => {
    console.log('CSV file successfully processed');
  });

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
  
const consumer = redpanda.consumer({ groupId: 'cupcake-group' })

const run = async () => {
    await consumer.connect()
    await consumer.subscribe({ topic: 'inv-count', fromBeginning: true })
  
    await consumer.run({
      eachMessage: async ({ topic, partition, message }) => {
        const messageData = JSON.parse(message.value.toString());
        const location = storeLocations[messageData.store];
        const { store, ...rest } = messageData;
         // Set the 'latest' property to false for all stores
         for (let store in inventory) {
            inventory[store].latest = false;
        }
  
        // Add the store to the inventory and set its 'latest' property to true
        inventory[messageData.store] = { ...rest, ...location, latest: true };
  
        console.log('Updated inventory:', inventory[messageData.store]);
  
        // Broadcast updated inventory to all connected clients
        wss.clients.forEach(function each(client) {
          if (client.readyState === WebSocket.OPEN) {
            client.send(JSON.stringify(inventory));
          }
        });
      },
    })
  }
  

run().catch(console.error)

module.exports = { inventory };