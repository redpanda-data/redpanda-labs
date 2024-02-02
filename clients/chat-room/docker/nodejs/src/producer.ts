import { Kafka } from "kafkajs";
const redpanda = new Kafka({
  brokers: ["localhost:19092"],
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