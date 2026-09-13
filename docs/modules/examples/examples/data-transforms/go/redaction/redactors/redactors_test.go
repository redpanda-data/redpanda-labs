package redactors

import (
	"github.com/pmw-rp/jsonparser"
	"testing"
)

func TestKeyValueRedactor(t *testing.T) {
	conf := RedactorConf{Name: "md5", Type: "key-value", Key: map[string]any{"function": "camelPrepend", "prefix": "hashed"}, Value: map[string]any{"function": "md5"}}
	redactor, err := buildRedactor(conf)
	if err != nil {
		t.Error(err)
		return
	}

	redaction := Redaction{
		Path:     "customer.firstName",
		Type:     "",
		Redactor: redactor,
	}

	sample := []byte("{\n  \"version\": 0,\n  \"id\": \"82afb36f-fb11-4104-9572-2e575a82cd79\",\n  \"createdAt\": \"2023-12-08T10:55:45.274475Z\",\n  \"lastUpdatedAt\": \"2023-12-08T10:55:45.274475Z\",\n  \"deliveredAt\": null,\n  \"completedAt\": null,\n  \"customer\": {\n    \"version\": 0,\n    \"id\": \"9240ad07-c1de-4fc4-abdd-9552864a17d1\",\n    \"firstName\": \"Nakia\",\n    \"lastName\": \"Terry\",\n    \"gender\": \"female\",\n    \"companyName\": null,\n    \"email\": \"ikekling@kuphal.org\",\n    \"customerType\": \"PERSONAL\",\n    \"revision\": 0\n  },\n  \"orderValue\": 16060,\n  \"lineItems\": [\n    {\n      \"articleId\": \"34d29db2-9377-4fb2-84f5-5f5279cb66e1\",\n      \"name\": \"Cucumber\",\n      \"quantity\": 50,\n      \"quantityUnit\": \"pieces\",\n      \"unitPrice\": 546,\n      \"totalPrice\": 27300\n    },\n    {\n      \"articleId\": \"a9156e56-4e38-451a-8906-33a588f62e67\",\n      \"name\": \"Shallots\",\n      \"quantity\": 282,\n      \"quantityUnit\": \"gram\",\n      \"unitPrice\": 376,\n      \"totalPrice\": 106032\n    },\n    {\n      \"articleId\": \"59466e0c-198b-4ec0-9650-ec213a48c0ba\",\n      \"name\": \"Okra\",\n      \"quantity\": 117,\n      \"quantityUnit\": \"pieces\",\n      \"unitPrice\": 233,\n      \"totalPrice\": 27261\n    },\n    {\n      \"articleId\": \"ac2e2d66-8816-4f9a-ac1e-6a3f6c448026\",\n      \"name\": \"Sorrel\",\n      \"quantity\": 150,\n      \"quantityUnit\": \"pieces\",\n      \"unitPrice\": 656,\n      \"totalPrice\": 98400\n    },\n    {\n      \"articleId\": \"fde99a61-ab7e-451a-8eba-7e318a61ecb2\",\n      \"name\": \"Kohlrabi\",\n      \"quantity\": 305,\n      \"quantityUnit\": \"pieces\",\n      \"unitPrice\": 482,\n      \"totalPrice\": 147010\n    },\n    {\n      \"articleId\": \"f44f2173-65d2-4e9f-bd0f-2f0a4293b78c\",\n      \"name\": \"Radicchio\",\n      \"quantity\": 16,\n      \"quantityUnit\": \"gram\",\n      \"unitPrice\": 259,\n      \"totalPrice\": 4144\n    },\n    {\n      \"articleId\": \"93b6555f-e91f-4cbb-bf6a-41625bed41fe\",\n      \"name\": \"Artichoke\",\n      \"quantity\": 109,\n      \"quantityUnit\": \"gram\",\n      \"unitPrice\": 301,\n      \"totalPrice\": 32809\n    },\n    {\n      \"articleId\": \"9cc7bee5-3361-487d-b2cd-45f9949a0d4c\",\n      \"name\": \"Horseradish\",\n      \"quantity\": 498,\n      \"quantityUnit\": \"gram\",\n      \"unitPrice\": 482,\n      \"totalPrice\": 240036\n    },\n    {\n      \"articleId\": \"3d168cf6-96c2-43df-a391-a2d82573c1ab\",\n      \"name\": \"Pepper\",\n      \"quantity\": 62,\n      \"quantityUnit\": \"pieces\",\n      \"unitPrice\": 442,\n      \"totalPrice\": 27404\n    },\n    {\n      \"articleId\": \"b365ed86-0755-4fbb-8e22-a01b3f63c908\",\n      \"name\": \"Carrot\",\n      \"quantity\": 184,\n      \"quantityUnit\": \"gram\",\n      \"unitPrice\": 122,\n      \"totalPrice\": 22448\n    },\n    {\n      \"articleId\": \"e824b6a6-73e9-451f-81ee-09a9739433ef\",\n      \"name\": \"Chicory\",\n      \"quantity\": 303,\n      \"quantityUnit\": \"gram\",\n      \"unitPrice\": 212,\n      \"totalPrice\": 64236\n    },\n    {\n      \"articleId\": \"7e11c212-45b9-4e79-a9ee-10345c12e856\",\n      \"name\": \"Broadbeans\",\n      \"quantity\": 119,\n      \"quantityUnit\": \"pieces\",\n      \"unitPrice\": 252,\n      \"totalPrice\": 29988\n    },\n    {\n      \"articleId\": \"eecb7079-c8e0-4096-89f5-d31287ea9b56\",\n      \"name\": \"Tomato\",\n      \"quantity\": 418,\n      \"quantityUnit\": \"gram\",\n      \"unitPrice\": 910,\n      \"totalPrice\": 380380\n    },\n    {\n      \"articleId\": \"df6c6903-533f-4172-a21d-897d4dc7177f\",\n      \"name\": \"Spaghetti Squash\",\n      \"quantity\": 231,\n      \"quantityUnit\": \"pieces\",\n      \"unitPrice\": 304,\n      \"totalPrice\": 70224\n    },\n    {\n      \"articleId\": \"a1b86c9f-c9ae-46dd-a858-7f2e28c89cff\",\n      \"name\": \"Asparagus\",\n      \"quantity\": 309,\n      \"quantityUnit\": \"pieces\",\n      \"unitPrice\": 361,\n      \"totalPrice\": 111549\n    },\n    {\n      \"articleId\": \"60f50bd2-8513-403d-bb78-87004d01693b\",\n      \"name\": \"Cucumber\",\n      \"quantity\": 307,\n      \"quantityUnit\": \"gram\",\n      \"unitPrice\": 376,\n      \"totalPrice\": 115432\n    },\n    {\n      \"articleId\": \"6269a36b-902a-403c-b1c3-51c26b584aec\",\n      \"name\": \"Dandelion Greens\",\n      \"quantity\": 388,\n      \"quantityUnit\": \"pieces\",\n      \"unitPrice\": 653,\n      \"totalPrice\": 253364\n    },\n    {\n      \"articleId\": \"d6e4388d-18b2-4526-ae0a-e8e7c6f6f222\",\n      \"name\": \"Horseradish\",\n      \"quantity\": 409,\n      \"quantityUnit\": \"gram\",\n      \"unitPrice\": 449,\n      \"totalPrice\": 183641\n    },\n    {\n      \"articleId\": \"1735178c-87d4-4191-ba92-0c956ce5a552\",\n      \"name\": \"Arrowroot\",\n      \"quantity\": 195,\n      \"quantityUnit\": \"pieces\",\n      \"unitPrice\": 90,\n      \"totalPrice\": 17550\n    },\n    {\n      \"articleId\": \"6d69cceb-2437-439d-9bec-4303f9eafb78\",\n      \"name\": \"Broccoli Rabe\",\n      \"quantity\": 263,\n      \"quantityUnit\": \"gram\",\n      \"unitPrice\": 759,\n      \"totalPrice\": 199617\n    },\n    {\n      \"articleId\": \"25c2c8ca-83ca-4582-8f07-22403019ad08\",\n      \"name\": \"Okra\",\n      \"quantity\": 193,\n      \"quantityUnit\": \"gram\",\n      \"unitPrice\": 856,\n      \"totalPrice\": 165208\n    },\n    {\n      \"articleId\": \"0550e675-7399-4ac1-9a6d-78423a0e7ad0\",\n      \"name\": \"Pepper\",\n      \"quantity\": 30,\n      \"quantityUnit\": \"gram\",\n      \"unitPrice\": 192,\n      \"totalPrice\": 5760\n    }\n  ],\n  \"payment\": {\n    \"paymentId\": \"e5c9f270-f2f5-4b07-a758-b5bb4e2154d4\",\n    \"method\": \"DEBIT\"\n  },\n  \"deliveryAddress\": {\n    \"version\": 0,\n    \"id\": \"521944eb-f6ab-4435-8dae-396662c65916\",\n    \"customer\": {\n      \"id\": \"9240ad07-c1de-4fc4-abdd-9552864a17d1\",\n      \"type\": \"PERSONAL\"\n    },\n    \"type\": \"INVOICE\",\n    \"firstName\": \"Nakia\",\n    \"lastName\": \"Terry\",\n    \"state\": \"Colorado\",\n    \"street\": \"47691 East Haven ville\",\n    \"houseNumber\": \"539\",\n    \"city\": \"Jarredfurt\",\n    \"zip\": \"25193\",\n    \"latitude\": -74.870911,\n    \"longitude\": -92.021109,\n    \"phone\": \"1-534-233-7207\",\n    \"additionalAddressInfo\": \"\",\n    \"createdAt\": \"2023-12-08T10:55:45.274525Z\",\n    \"revision\": 0\n  },\n  \"revision\": 0\n}\n")

	deltas, err := redaction.apply(sample)

	redacted, err := jsonparser.Apply(deltas, sample)

	_ = redacted

	//expectedKey := "hashedFoo"
	//redactedKey := api.key
	//if strings.Compare(redactedKey, expectedKey) != 0 {
	//	t.Errorf("\nexpected:\n%s\ngot:\n%s", expectedKey, redactedKey)
	//}
	//
	//expectedValue := "37b51d194a7513e45b56f6524f2d51f2"
	//redactedValue := api.value.(string)
	//if strings.Compare(redactedValue, expectedValue) != 0 {
	//	t.Errorf("\nexpected:\n%s\ngot:\n%s", expectedValue, redactedValue)
	//}
}
