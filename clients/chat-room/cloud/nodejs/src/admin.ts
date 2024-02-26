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
const admin = redpanda.admin();
export async function createTopic(
  topic: string,
  partitions?: number,
  replicas?: number
) {
  await admin.connect();
  const existingTopics = await admin.listTopics();
  if (!existingTopics.includes(topic)) {
    await admin.createTopics({
      topics: [
        {
          topic: topic,
          numPartitions: partitions ? partitions : 1,
          replicationFactor: replicas ? replicas : 1,
        },
      ],
    });
  }
  await admin.disconnect();
}