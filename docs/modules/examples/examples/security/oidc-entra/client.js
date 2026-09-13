// client.js

import { Kafka } from 'kafkajs'
import dotenv from 'dotenv'
import { jwtDecode } from 'jwt-decode'
import { ClientCredentials } from 'simple-oauth2'

dotenv.config()

// Load configuration from environment variables
const {
  TENANT_ID,
  OIDC_CLIENT_ID,
  OIDC_CLIENT_SECRET,
} = process.env

if (!TENANT_ID || !OIDC_CLIENT_ID || !OIDC_CLIENT_SECRET) {
  throw new Error('Missing required environment variables. Check TENANT_ID, OIDC_CLIENT_ID, OIDC_CLIENT_SECRET.')
}

// Set up OAuth 2.0 client credentials configuration
const tokenHost = `https://login.microsoftonline.com/${TENANT_ID}`
const tokenPath = `${tokenHost}/oauth2/v2.0/token`

const client = new ClientCredentials({
  client: {
    id: OIDC_CLIENT_ID,
    secret: OIDC_CLIENT_SECRET,
  },
  auth: {
    tokenHost,
    tokenPath,
  },
})

let accessToken = null

// Fetches and caches an access token using the OAuth2 client credentials flow.
// Optionally decodes the token for inspection, and uses it in KafkaJS SASL/OAUTHBEARER authentication.
async function getToken() {
  const shouldFetch =
    !accessToken ||
    typeof accessToken.expired !== 'function' ||
    accessToken.expired();

  if (shouldFetch) {
    console.log('[OIDC] Fetching new access token...')

    try {
      accessToken = await client.getToken({
        scope: `api://${OIDC_CLIENT_ID}/.default`,
      })
    } catch (err) {
      console.error('[OIDC] Failed to get token:', err.message)
      throw err
    }
  }

  return {
    value: accessToken.token.access_token,
    // extensions: {}, // optionally add OAUTHBEARER extensions here
  }
}

// Decode token and extract the `sub` claim for ACLs
async function getSubValue() {
  const { value } = await getToken()
  const decoded = jwtDecode(value)
  console.log('[OIDC] Decoded token:')
  console.log(JSON.stringify(decoded, null, 2))
  console.log(`\nSub (use in ACLs): ${decoded.sub}`)
}

// Configure KafkaJS with SASL/OAUTHBEARER using the OAuth token
const kafka = new Kafka({
  clientId: 'my-app',
  brokers: ['localhost:19092'],
  ssl: false, // Change to `true` if TLS is enabled on your Redpanda brokers
  sasl: {
    mechanism: 'oauthbearer',
    oauthBearerProvider: getToken,
  },
})

async function sendKafkaMessage() {
  const producer = kafka.producer()

  try {
    console.log('[Kafka] Connecting producer...')
    await producer.connect()

    console.log('[Kafka] Sending message...')
    await producer.send({
      topic: 'test-topic',
      messages: [{ value: 'Hello from a secure OIDC client!' }],
    })

    console.log('[Kafka] Message sent successfully.')
  } catch (err) {
    console.error('[Kafka] Error during produce:', err)
  } finally {
    await producer.disconnect()
    console.log('[Kafka] Producer disconnected.')
  }
}

// Support CLI argument for fetching `sub` value
const arg = process.argv[2]

if (arg === 'get-sub-value') {
  await getSubValue()
} else {
  await sendKafkaMessage()
}
