import { Kafka } from "kafkajs";
const redpanda = new Kafka({
  brokers: ["<bootstrap-server-address>"],
  ssl: {
    },
  sasl: {
    mechanism: "scram-sha-256",
    username: "redpanda-chat-account",
    password: "<password>"
  }
});
const producer = redpanda.producer();
export async function getConnection(user: string) {
  try {
    await producer.connect();
    return async (message: string) => {
      await producer.send({
        topic: "chat-room",
        messages: [{ value: JSON.stringify({ message, user }) }],
      });
    };
  } catch (error) {
    console.error("Error:", error);
  }
}
export async function disconnect() {
  try {
    await producer.disconnect();
  } catch (error) {
    console.error("Error:", error);
  }
}