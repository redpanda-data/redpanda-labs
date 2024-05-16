use anyhow::bail;
use apache_avro::Schema;
use apache_avro::types::Value;
use chrono::{Datelike, DateTime, TimeZone, Utc};
use redpanda_transform_sdk::{BorrowedRecord, RecordWriter, WriteEvent};
use redpanda_transform_sdk_sr::{SchemaFormat, SchemaId, SchemaRegistryClient};

use crate::{Mode, Precision, TargetType};
use crate::schema::decompose;

const SECONDS_IN_A_DAY: i64 = 86_400;

/// Convert the given Redpanda Schema to a new form based on the given [`TargetType`].
pub fn convert_schema(
    input: &redpanda_transform_sdk_sr::Schema,
    mode: &Mode,
    target_type: &TargetType,
) -> anyhow::Result<redpanda_transform_sdk_sr::Schema> {
    if !input.format().eq(&SchemaFormat::Avro) {
        bail!("invalid SchemaFormat: not Avro");
    }
    let input_avro = Schema::parse_str(input.schema())?;

    // Bit messy...but validate we can convert to the target correctly.
    if mode.field().is_some() {
        // We're targeting a Record field.
        let field_name = mode.field().unwrap().as_str();
        match input_avro {
            Schema::Record(r) => {
                let mut new_schema = r.clone();
                for field in new_schema.fields.iter_mut() {
                    if field.name == field_name {
                        // TODO: preserve/convert default values?
                        field.default = None;
                        field.schema = match target_type {
                            TargetType::String(_) => Schema::String,
                            TargetType::Unix(_) => Schema::Long,
                            TargetType::Date => Schema::Date,
                            TargetType::Time => Schema::TimeMicros,
                        };
                    }
                }
                // TODO: This implementation does not support references currently
                Ok(redpanda_transform_sdk_sr::Schema::new_avro(
                    Schema::Record(new_schema).canonical_form(),
                    Vec::new(),
                ))
            }
            _ => bail!("cannot operate in field mode on non-Record Avro schema"),
        }
    } else {
        // Simple conversion based on TargetType
        let schema = match target_type {
            TargetType::String(_) => Schema::String,
            TargetType::Unix(_) => Schema::Long,
            TargetType::Date => Schema::Date,
            TargetType::Time => Schema::TimeMicros,
        };
        Ok(redpanda_transform_sdk_sr::Schema::new_avro(
            schema.canonical_form(),
            Vec::new(),
        ))
    }
}

/// The main conversion logic for Avro data.
pub fn convert_event(
    event: WriteEvent,
    writer: &mut RecordWriter,
    output_topic: &String,
    mode: &Mode,
    target_type: &TargetType,
    sr: &SchemaRegistryClient,
    fmt: Option<&String>,
) -> anyhow::Result<()> {
    // Pass record through quickly if we have nothing to process.
    let record = event.record;
    let (mode_str, payload) = if mode.is_key() {
        ("key", record.key())
    } else {
        ("value", record.value())
    };
    if payload.is_none() {
        // TODO: error handling for the pass-through case.
        return Ok(writer.write(record)?);
    }

    // Fetch and parse the Avro schema. Ideally, we'd be able to cache the result.
    let (id, mut data) = match decompose(payload.unwrap()) {
        Ok(tuple) => tuple,
        Err(e) => bail!("failed to parse Avro framing: {:?}", e),
    };
    let raw_schema = match sr.lookup_schema_by_id(SchemaId(id)) {
        Ok(s) => s,
        Err(_) => bail!("failed to find schema for id {}", id),
    };
    let schema = match raw_schema.format() {
        SchemaFormat::Avro => Schema::parse_str(raw_schema.schema())?,
        _ => bail!("unsupported schema type: schema is not Avro"),
    };

    // Fetch or create the new output schema.
    // TODO: move this?
    let subject = format!("{}-{}", output_topic, mode_str);
    let output_subject = match sr.lookup_latest_schema(subject.clone()) {
        Ok(s) => s,
        Err(e) => bail!("failed to find schema for subject {}: {:?}", subject, e),
    };
    let output_schema = match Schema::parse_str(output_subject.schema().schema()) {
        Ok(s) => s,
        Err(e) => bail!("failed to parse schema: {:?}", e),
    };

    // Deserialize the data into an Avro value.
    // XXX: for now, we need to frame the data ourselves :'(
    // TODO: garbage data needs to go either to a DLQ or just be produced as-is otherwise
    //       the transform ends up stuck on the record if we panic...or I guess dropped?
    let value = match apache_avro::from_avro_datum(&schema, &mut data, None) {
        Ok(v) => v,
        Err(e) => bail!("failed to deserialize Avro data: {:?}", e),
    };
    let converted = match convert_value(&value, mode, target_type, fmt) {
        Ok(v) => v,
        Err(e) => bail!("failed to convert Avro data: {:?}", e),
    };
    let mut serialized = match apache_avro::to_avro_datum(&output_schema, converted) {
        Ok(v) => v,
        Err(e) => bail!("failed to serialize converted Avro data: {:?}", e),
    };
    let mut framed: Vec<u8> = Vec::new();
    framed.push(0);
    for byte in output_subject.id().0.to_be_bytes() {
        framed.push(byte);
    }
    framed.append(&mut serialized);

    // Write it out.
    let output = if mode.is_key() {
        BorrowedRecord::new(Some(framed.as_slice()), record.value())
    } else {
        BorrowedRecord::new(record.key(), Some(framed.as_slice()))
    };
    match writer.write(output) {
        Ok(_) => Ok(()),
        Err(e) => {
            // XXX not sure that this would be recoverable...what's the error handling on the broker?
            eprintln!("failed to write event: {:?}", e);
            Ok(())
        }
    }
}

/// Scale `value` from one precision to another.
fn scale(value: i64, from: Precision, to: Precision) -> i64 {
    match (from, to) {
        (Precision::Seconds, Precision::Milliseconds) => value * 1_000,
        (Precision::Seconds, Precision::Microseconds) => value * 1_000_000,
        (Precision::Seconds, Precision::Nanoseconds) => value * 1_000_000_000,
        (Precision::Milliseconds, Precision::Seconds) => value / 1_000,
        (Precision::Milliseconds, Precision::Microseconds) => value * 1_000,
        (Precision::Milliseconds, Precision::Nanoseconds) => value * 1_000_000,
        (Precision::Microseconds, Precision::Seconds) => value / 1_000_000,
        (Precision::Microseconds, Precision::Milliseconds) => value / 1_000,
        (Precision::Microseconds, Precision::Nanoseconds) => value * 1_000,
        (Precision::Nanoseconds, Precision::Seconds) => value / 1_000_000_000,
        (Precision::Nanoseconds, Precision::Milliseconds) => value / 1_000_000,
        (Precision::Nanoseconds, Precision::Microseconds) => value / 1_000,
        _ => value,
    }
}

fn convert_value(
    value: &Value,
    mode: &Mode,
    target_type: &TargetType,
    fmt: Option<&String>,
) -> anyhow::Result<Value> {
    match value {
        Value::Record(rows) => {
            let field_name = match mode.field() {
                None => bail!("cannot convert Avro record using mode {:?}", mode),
                Some(f) => f,
            };
            let mut new_record: Vec<(String, Value)> = rows.clone();
            for (field, value) in new_record.iter_mut() {
                if field.as_str() == field_name.as_str() {
                    *value = convert_value(value, mode, target_type, fmt)?;
                }
            }
            Ok(Value::Record(new_record))
        }
        Value::Int(i) => convert(*i as i64, Precision::Seconds, target_type),
        Value::Long(l) => convert(*l, Precision::Milliseconds, target_type),
        Value::String(s) => {
            let result = match fmt {
                None => DateTime::parse_from_rfc3339(s.as_str()),
                Some(fmt) => DateTime::parse_from_str(s.as_str(), fmt.as_str()),
            };
            let dt = match result {
                Ok(dt) => dt,
                Err(e) => bail!("parse error: {:?}", e),
            };
            let nanos = match dt.timestamp_nanos_opt() {
                None => dt.timestamp_micros() * 1_000, // fudge to nano precision
                Some(n) => n,
            };
            convert(nanos, Precision::Nanoseconds, target_type)
        }
        Value::Date(d) => convert(
            (*d as i64) * SECONDS_IN_A_DAY,
            Precision::Seconds,
            target_type,
        ),
        Value::TimestampMillis(ts_ms) => convert(*ts_ms, Precision::Milliseconds, target_type),
        Value::TimestampMicros(ts_us) => convert(*ts_us, Precision::Microseconds, target_type),
        Value::LocalTimestampMillis(ts_ms) => convert(*ts_ms, Precision::Milliseconds, target_type),
        Value::LocalTimestampMicros(ts_us) => convert(*ts_us, Precision::Microseconds, target_type),
        _ => bail!("unsupported Avro type"),
    }
}

/// We assume any 64-bit integer is representing Epoch time in milliseconds.
fn convert(long: i64, precision: Precision, target_type: &TargetType) -> anyhow::Result<Value> {
    // Short-cut if using TargetType::Unix
    if target_type.is_unix() {
        return Ok(Value::Long(scale(
            long,
            precision,
            target_type.precision().unwrap(),
        )));
    }

    let dt = match precision {
        Precision::Seconds => chrono::DateTime::from_timestamp(long, 0),
        Precision::Milliseconds => chrono::DateTime::from_timestamp_millis(long),
        Precision::Microseconds => chrono::DateTime::from_timestamp_micros(long),
        Precision::Nanoseconds => Some(chrono::DateTime::from_timestamp_nanos(long)),
    }
    .unwrap();

    match target_type {
        TargetType::String(items) => Ok(Value::String(
            dt.format_with_items(items.as_slice().iter()).to_string(),
        )),
        TargetType::Date => Ok(Value::Date(
            dt.signed_duration_since(DateTime::UNIX_EPOCH).num_days() as i32,
        )),
        TargetType::Time => {
            // This is funky...but we need to compute just the "time" since midnight.
            let midnight = Utc
                .with_ymd_and_hms(dt.year(), dt.month(), dt.day(), 0, 0, 0)
                .unwrap();
            let delta = dt.signed_duration_since(midnight);
            Ok(Value::TimeMicros(delta.num_microseconds().unwrap()))
        }
        _ => bail!("unhandled target type"),
    }
}

#[cfg(test)]
mod tests {
    use std::time::SystemTime;

    use apache_avro::types::Value;
    use redpanda_transform_sdk::{
        BorrowedRecord, RecordSink, RecordWriter, WriteError, WriteEvent, WriteOptions,
        WrittenRecord,
    };
    use redpanda_transform_sdk_sr::{
        Schema, SchemaId, SchemaRegistryClient, SchemaRegistryClientImpl, SchemaRegistryError,
        SchemaVersion, SubjectSchema,
    };

    use crate::{avro, Mode, Precision, TargetType};
    use crate::avro::convert_value;
    use crate::schema::MAGIC_BYTES;

    const STRING_ISO8601: &str = "2024-01-03T19:38:06.988762314Z";
    const STRING_ISO8601_MILLIS: &str = "2024-01-03T19:38:06.988Z";
    const STRING_DATE_ONLY: &str = "2024-01-03";
    const STRING_TIME_ONLY: &str = "19:38";

    const SECONDS: i64 = 1704310686;
    const MILLIS: i64 = 1704310686988;
    const MICROS: i64 = 1704310686988762;
    const NANOS: i64 = 1704310686988762314;
    const DAYS: i32 = 19725;
    const TIME_OF_DAY_IN_MICROSECONDS: i64 = 70686988762;
    const TIME_OF_DAY_IN_MILLIS: i64 = 70686988;
    const TIME_OF_DAY_IN_SECONDS: i64 = 70686;

    const UNIX_PRECISION_TESTS: [(Value, TargetType, Value); 16] = [
        (
            Value::Int(SECONDS as i32),
            TargetType::Unix(Precision::Seconds),
            Value::Long(SECONDS),
        ),
        (
            Value::Int(SECONDS as i32),
            TargetType::Unix(Precision::Milliseconds),
            Value::Long(SECONDS * 1_000),
        ),
        (
            Value::Int(SECONDS as i32),
            TargetType::Unix(Precision::Microseconds),
            Value::Long(SECONDS * 1_000 * 1_000),
        ),
        (
            Value::Int(SECONDS as i32),
            TargetType::Unix(Precision::Nanoseconds),
            Value::Long(SECONDS * 1_000 * 1_000 * 1_000),
        ),
        (
            Value::Long(MILLIS),
            TargetType::Unix(Precision::Seconds),
            Value::Long(SECONDS),
        ),
        (
            Value::Long(MILLIS),
            TargetType::Unix(Precision::Milliseconds),
            Value::Long(MILLIS),
        ),
        (
            Value::Long(MILLIS),
            TargetType::Unix(Precision::Microseconds),
            Value::Long(MILLIS * 1_000),
        ),
        (
            Value::Long(MILLIS),
            TargetType::Unix(Precision::Nanoseconds),
            Value::Long(MILLIS * 1_000 * 1_000),
        ),
        (
            Value::TimestampMillis(MILLIS),
            TargetType::Unix(Precision::Seconds),
            Value::Long(SECONDS),
        ),
        (
            Value::TimestampMillis(MILLIS),
            TargetType::Unix(Precision::Milliseconds),
            Value::Long(MILLIS),
        ),
        (
            Value::TimestampMillis(MILLIS),
            TargetType::Unix(Precision::Microseconds),
            Value::Long(MILLIS * 1_000),
        ),
        (
            Value::TimestampMillis(MILLIS),
            TargetType::Unix(Precision::Nanoseconds),
            Value::Long(MILLIS * 1_000_000),
        ),
        (
            Value::TimestampMicros(MICROS),
            TargetType::Unix(Precision::Seconds),
            Value::Long(SECONDS),
        ),
        (
            Value::TimestampMicros(MICROS),
            TargetType::Unix(Precision::Milliseconds),
            Value::Long(MILLIS),
        ),
        (
            Value::TimestampMicros(MICROS),
            TargetType::Unix(Precision::Microseconds),
            Value::Long(MICROS),
        ),
        (
            Value::TimestampMicros(MICROS),
            TargetType::Unix(Precision::Nanoseconds),
            Value::Long(MICROS * 1_000),
        ),
    ];

    #[test]
    fn test_simple_epoch_conversions() {
        let mode = Mode::Value;
        for (input, target, expected) in UNIX_PRECISION_TESTS {
            println!(
                "testing epoch conversion: {:?}, {:?} => {:?}",
                input, target, expected
            );
            assert_eq!(
                expected,
                convert_value(&input, &mode, &target, None).unwrap()
            );
        }
    }

    const TIME_CONVERSION_TESTS: [(Value, TargetType, Value); 3] = [
        (
            Value::Int(SECONDS as i32),
            TargetType::Time,
            Value::TimeMicros(TIME_OF_DAY_IN_SECONDS * 1_000_000),
        ),
        (
            Value::Long(MILLIS),
            TargetType::Time,
            Value::TimeMicros(TIME_OF_DAY_IN_MILLIS * 1_000),
        ),
        (
            Value::TimestampMicros(MICROS),
            TargetType::Time,
            Value::TimeMicros(TIME_OF_DAY_IN_MICROSECONDS),
        ),
    ];

    #[test]
    fn test_time_conversions() {
        let mode = Mode::Value;
        for (input, target, expected) in TIME_CONVERSION_TESTS {
            println!(
                "testing time conversion: {:?}, {:?} => {:?}",
                input, target, expected
            );
            assert_eq!(
                expected,
                convert_value(&input, &mode, &target, None).unwrap()
            );
        }
    }

    const TO_STRING_TESTS: [(Value, &str, fn() -> Value); 5] = [
        (Value::Int(SECONDS as i32), "string[%Y-%m-%d]", || {
            Value::String(String::from(STRING_DATE_ONLY))
        }),
        (Value::Long(MILLIS), "string[%Y-%m-%d]", || {
            Value::String(String::from(STRING_DATE_ONLY))
        }),
        (Value::TimestampMillis(MILLIS), "string[%Y-%m-%d]", || {
            Value::String(String::from(STRING_DATE_ONLY))
        }),
        (Value::TimestampMicros(MICROS), "string[%Y-%m-%d]", || {
            Value::String(String::from(STRING_DATE_ONLY))
        }),
        (Value::Date(DAYS), "string[%Y-%m-%d]", || {
            Value::String(String::from(STRING_DATE_ONLY))
        }),
    ];

    #[test]
    fn test_to_string_conversions() {
        let mode = Mode::Value;
        for (input, fmt, f) in TO_STRING_TESTS {
            let expected = f();
            let target = TargetType::try_from(String::from(fmt)).unwrap();
            println!(
                "testing from string conversion: {:?}, {:?} => {:?}",
                input, fmt, expected
            );
            assert_eq!(
                expected,
                convert_value(&input, &mode, &target, None).unwrap()
            );
        }
    }

    const FROM_STRING_TESTS: [(&str, TargetType, Value); 6] = [
        (
            STRING_ISO8601,
            TargetType::Unix(Precision::Seconds),
            Value::Long(SECONDS),
        ),
        (
            STRING_ISO8601,
            TargetType::Unix(Precision::Milliseconds),
            Value::Long(MILLIS),
        ),
        (
            STRING_ISO8601,
            TargetType::Unix(Precision::Microseconds),
            Value::Long(MICROS),
        ),
        (
            STRING_ISO8601,
            TargetType::Unix(Precision::Nanoseconds),
            Value::Long(NANOS),
        ),
        (
            STRING_ISO8601,
            TargetType::Time,
            Value::TimeMicros(TIME_OF_DAY_IN_MICROSECONDS),
        ),
        (STRING_ISO8601, TargetType::Date, Value::Date(DAYS)),
    ];
    #[test]
    fn test_from_string_conversions() {
        let mode = Mode::Value;
        for (input, target, expected) in FROM_STRING_TESTS {
            let value = Value::String(String::from(input));
            println!(
                "testing to string conversion: {:?}, {:?} => {:?}",
                value, target, expected
            );
            assert_eq!(
                expected,
                convert_value(&value, &mode, &target, None).unwrap()
            );
        }
    }

    const STRING_TO_STRING_TESTS: [(&str, &str, fn() -> Value); 2] = [
        (STRING_ISO8601, "string[%Y-%m-%d]", || {
            Value::String(String::from(STRING_DATE_ONLY))
        }),
        (STRING_ISO8601, "string[%H:%M]", || {
            Value::String(String::from(STRING_TIME_ONLY))
        }),
    ];

    #[test]
    fn test_string_to_string_conversions() {
        let mode = Mode::Value;
        for (input, target_fmt, f) in STRING_TO_STRING_TESTS {
            let value = Value::String(String::from(input));
            let target = TargetType::try_from(String::from(target_fmt)).unwrap();
            let expected = f();
            println!(
                "testing string to string conversion: {:?}, {:?} => {:?}",
                value, target, expected
            );
            assert_eq!(
                expected,
                convert_value(&value, &mode, &target, None).unwrap()
            );
        }
    }

    const FIELD_CONVERSION_TESTS: [(
        fn() -> Vec<(String, Value)>,
        &str,
        TargetType,
        fn() -> Vec<(String, Value)>,
    ); 1] = [(
        || {
            vec![
                (String::from("a"), Value::Long(MILLIS)),
                (String::from("b"), Value::Boolean(true)),
            ]
        },
        "a",
        TargetType::Unix(Precision::Seconds),
        || {
            vec![
                (String::from("a"), Value::Long(SECONDS)),
                (String::from("b"), Value::Boolean(true)),
            ]
        },
    )];

    #[test]
    fn test_field_conversion() {
        for (input, field, target, output) in FIELD_CONVERSION_TESTS {
            let value = Value::Record(input());
            let expected = Value::Record(output());
            let mode = Mode::ValueField(String::from(field));
            println!(
                "testing field conversion: {:?}, {:?}, {:?} => {:?}",
                value, mode, target, expected
            );
            assert_eq!(
                expected,
                convert_value(&value, &mode, &target, None).unwrap()
            )
        }
    }

    struct DummyWriter {
        pub key: Vec<u8>,
        pub value: Vec<u8>,
    }
    impl RecordSink for DummyWriter {
        fn write(
            &mut self,
            r: BorrowedRecord<'_>,
            _opts: WriteOptions<'_>,
        ) -> Result<(), WriteError> {
            self.key.clear();
            self.value.clear();

            if r.key().is_some() {
                for byte in r.key().unwrap() {
                    self.key.push(*byte);
                }
            }
            if r.value().is_some() {
                for byte in r.value().unwrap() {
                    self.value.push(*byte);
                }
            }
            Ok(())
        }
    }

    struct DummySchemaRegistryClient {
        pub input: Schema,
        pub output: Schema,
    }

    impl SchemaRegistryClientImpl for DummySchemaRegistryClient {
        fn lookup_schema_by_id(&self, id: SchemaId) -> redpanda_transform_sdk_sr::Result<Schema> {
            if id.0 == 1 {
                Ok(self.input.clone())
            } else {
                Err(SchemaRegistryError::InvalidSchema)
            }
        }

        fn lookup_schema_by_version(
            &self,
            _subject: &str,
            _version: SchemaVersion,
        ) -> redpanda_transform_sdk_sr::Result<SubjectSchema> {
            Err(SchemaRegistryError::Unknown(1))
        }

        fn lookup_latest_schema(
            &self,
            subject: &str,
        ) -> redpanda_transform_sdk_sr::Result<SubjectSchema> {
            if subject.starts_with("input") {
                Ok(SubjectSchema::new(
                    self.input.clone(),
                    subject,
                    SchemaVersion(1),
                    SchemaId(1),
                ))
            } else if subject.starts_with("output") {
                Ok(SubjectSchema::new(
                    self.output.clone(),
                    subject,
                    SchemaVersion(1),
                    SchemaId(1),
                ))
            } else {
                Err(SchemaRegistryError::InvalidSchema)
            }
        }

        fn create_schema(
            &mut self,
            subject: &str,
            schema: Schema,
        ) -> redpanda_transform_sdk_sr::Result<SubjectSchema> {
            Ok(SubjectSchema::new(
                schema,
                subject,
                SchemaVersion(1),
                SchemaId(1),
            ))
        }
    }
    #[test]
    fn integration_test() {
        // Generate an input event containing an encoded epoch datetime.
        let input = Value::Long(MILLIS);
        let input_avro_schema =
            apache_avro::Schema::parse_str(r#"{ "type": "long", "name": "epoch" }"#).unwrap();
        let mut value = vec![MAGIC_BYTES[0], 0, 0, 0, 1]; // schema id "1"
        apache_avro::to_avro_datum(&input_avro_schema, input.clone())
            .unwrap()
            .iter()
            .for_each(|byte| value.push(*byte));
        let event = WriteEvent {
            record: WrittenRecord::new(None, Some(value.as_slice()), SystemTime::now()),
        };

        // Stub out our test writer.
        let mut writer = DummyWriter {
            key: Vec::new(),
            value: Vec::new(),
        };
        let mut record_writer = RecordWriter::new(&mut writer);

        // Stub out the Schema Registry client.
        let output_avro_schema =
            apache_avro::Schema::parse_str(r#"{ "type": "string", "name": "epoch" }"#).unwrap();
        let input_schema = Schema::new_avro(input_avro_schema.canonical_form(), Vec::new());
        let output_schema = Schema::new_avro(output_avro_schema.canonical_form(), Vec::new());
        let sr = SchemaRegistryClient::new_wrapping(Box::new(DummySchemaRegistryClient {
            input: input_schema,
            output: output_schema,
        }));

        // Configure value conversion to String output.
        let mode = Mode::Value;
        let target_type =
            TargetType::try_from(String::from("string[%Y-%m-%dT%H:%M:%S%.fZ]")).unwrap();

        // Do the conversion.
        avro::convert_event(
            event,
            &mut record_writer,
            &String::from("output"),
            &mode,
            &target_type,
            &sr,
            None,
        )
        .unwrap();

        assert!(writer.key.is_empty(), "should have an empty key");
        assert_eq!(
            MAGIC_BYTES[0],
            *writer.value.get(0).unwrap(),
            "should have magic byte"
        );
        assert_eq!(
            1i32.to_be_bytes(),
            writer.value[1..5],
            "should have schema id in frame"
        );

        let payload = writer.value.split_off(5);
        let output =
            apache_avro::from_avro_datum(&output_avro_schema, &mut payload.as_slice(), None)
                .unwrap();
        println!(
            "integration testing Avro conversion {:?} -> {:?}",
            input,
            output.clone()
        );
        match output {
            Value::String(s) => assert_eq!(
                STRING_ISO8601_MILLIS,
                s.as_str(),
                "should get epoch formatted to ISO8601 format"
            ),
            _ => panic!("value should have been a Value::String!"),
        }
    }
}
