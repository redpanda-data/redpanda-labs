use anyhow::bail;
use std::env;
use std::fmt::Debug;

use chrono::format::{Item, StrftimeItems};
use redpanda_transform_sdk::*;
use redpanda_transform_sdk_sr::{SchemaFormat, SchemaRegistryClient};

mod avro;
mod schema;

const ENV_MODE: &str = "TIMESTAMP_MODE";
const ENV_TARGET_TYPE: &str = "TIMESTAMP_TARGET_TYPE";
const ENV_INPUT_TOPIC: &str = "REDPANDA_INPUT_TOPIC";
const ENV_OUTPUT_TOPIC: &str = "REDPANDA_OUTPUT_TOPIC_0";

/// Optional format string for converting strings to another target type.
const ENV_FORMAT: &str = "TIMESTAMP_STRING_FORMAT";

/// The `chrono` parser accepts patterns that may result in no information being printed,
/// such as just having a bunch of fixed literals. That would silently cause data to be
/// dropped in the transform, so we do a validation step after parsing to see if we have
/// any items that would print actual parts of the timestamp.
fn parse_format(fmt: &str) -> anyhow::Result<Vec<Item<'static>>> {
    match StrftimeItems::new(fmt).parse_to_owned() {
        Ok(items) => {
            if items
                .iter()
                .find(|&i| match i {
                    Item::Numeric(_, _) => true,
                    Item::Fixed(_) => true,
                    _ => false,
                })
                .is_some()
            {
                Ok(items)
            } else {
                bail!("invalid datetime format: will result in data loss")
            }
        }
        Err(e) => bail!("parse error: {}", e),
    }
}

/// Whether we're converting the Key or the Value of the Record.
/// Defaults to [`Mode::Value`].
#[derive(Debug, Clone, PartialEq, Eq)]
enum Mode {
    Key,
    KeyField(String),
    Value,
    ValueField(String),
}

impl Mode {
    fn is_key(&self) -> bool {
        match self {
            Mode::Key => true,
            Mode::KeyField(_) => true,
            Mode::Value => false,
            Mode::ValueField(_) => false,
        }
    }

    #[allow(dead_code)]
    fn is_value(&self) -> bool {
        !self.is_key()
    }

    fn field(&self) -> Option<&String> {
        match self {
            Mode::Key => None,
            Mode::KeyField(s) => Some(s),
            Mode::Value => None,
            Mode::ValueField(s) => Some(s),
        }
    }
}

impl TryFrom<String> for Mode {
    type Error = &'static str;

    fn try_from<'a>(value: String) -> Result<Self, Self::Error> {
        if value.eq_ignore_ascii_case("key") {
            Ok(Mode::Key)
        } else if value.eq_ignore_ascii_case("value") {
            Ok(Mode::Value)
        } else if value.ends_with(']') && value.contains('[') {
            match value
                .trim_end_matches(']')
                .split_at(value.find('[').unwrap())
            {
                (prefix, field) => {
                    if prefix.eq_ignore_ascii_case("key") {
                        let f = field.trim_start_matches('[').trim();
                        if f.is_empty() {
                            Err("invalid mode")
                        } else {
                            Ok(Mode::KeyField(String::from(f)))
                        }
                    } else if prefix.eq_ignore_ascii_case("value") {
                        let f = field.trim_start_matches('[').trim();
                        if f.is_empty() {
                            Err("invalid mode")
                        } else {
                            Ok(Mode::ValueField(String::from(f)))
                        }
                    } else {
                        Err("invalid mode")
                    }
                }
            }
        } else {
            Err("invalid mode")
        }
    }
}

/// The desired precision for the timestamp.
#[derive(Debug, Copy, Clone, Eq, PartialEq)]
enum Precision {
    Seconds,
    Milliseconds,
    Microseconds,
    Nanoseconds,
}

impl TryFrom<String> for Precision {
    type Error = &'static str;

    fn try_from(value: String) -> Result<Self, Self::Error> {
        match value.to_ascii_lowercase().as_str() {
            "seconds" => Ok(Precision::Seconds),
            "s" => Ok(Precision::Seconds),
            "milliseconds" => Ok(Precision::Milliseconds),
            "ms" => Ok(Precision::Milliseconds),
            "microseconds" => Ok(Precision::Microseconds),
            "us" => Ok(Precision::Microseconds),
            "nanoseconds" => Ok(Precision::Nanoseconds),
            "ns" => Ok(Precision::Nanoseconds),
            _ => Err("invalid precision"),
        }
    }
}

/// The desired target timestamp representation.
#[derive(Debug, Clone, PartialEq, Eq)]
enum TargetType {
    String(Vec<Item<'static>>),
    Unix(Precision),
    Date,
    Time,
}

impl TargetType {
    fn is_unix(&self) -> bool {
        match self {
            TargetType::Unix(_) => true,
            _ => false,
        }
    }

    fn precision(&self) -> Option<Precision> {
        match self {
            TargetType::Unix(p) => Some(*p),
            _ => None,
        }
    }
}

impl TryFrom<String> for TargetType {
    type Error = &'static str;

    fn try_from(value: String) -> Result<Self, Self::Error> {
        if value.eq_ignore_ascii_case("date") {
            Ok(TargetType::Date)
        } else if value.eq_ignore_ascii_case("time") {
            Ok(TargetType::Time)
        } else if value.eq_ignore_ascii_case("unix") {
            // Default to second-level precision.
            Ok(TargetType::Unix(Precision::Seconds))
        } else if value.ends_with(']') && value.contains('[') {
            match value
                .trim_end_matches(']')
                .split_at(value.find('[').unwrap())
            {
                (prefix, var) => {
                    if prefix.eq_ignore_ascii_case("string") {
                        let v = var.trim_start_matches('[').trim();
                        if v.is_empty() {
                            Err("invalid target type")
                        } else {
                            match parse_format(v) {
                                Ok(items) => Ok(TargetType::String(items)),
                                Err(_) => Err("invalid string target format"),
                            }
                        }
                    } else if prefix.eq_ignore_ascii_case("unix") {
                        let v = var.trim_start_matches('[').trim();
                        if v.is_empty() {
                            Err("invalid target type")
                        } else {
                            match Precision::try_from(String::from(v)) {
                                Ok(p) => Ok(TargetType::Unix(p)),
                                _ => Err("invalid precision"),
                            }
                        }
                    } else {
                        Err("invalid target type")
                    }
                }
            }
        } else {
            Err("invalid target type")
        }
    }
}

fn main() -> anyhow::Result<()> {
    // Identify our configuration from the environment. This is a lot of error handling to avoid
    // barfing unintelligible wasm stack traces.
    let mode = match env::var(ENV_MODE).map_or(Ok(Mode::Value), Mode::try_from) {
        Ok(m) => m,
        Err(e) => bail!("failure parsing mode: {}", e),
    };
    let target_type = match TargetType::try_from(env::var(ENV_TARGET_TYPE).unwrap_or(String::new()))
    {
        Ok(t) => t,
        Err(e) => bail!("failure parsing target type: {}", e),
    };

    let input_topic = match env::var(ENV_INPUT_TOPIC) {
        Ok(t) => t,
        Err(_) => bail!(
            "no input topic found in environment value {}",
            ENV_INPUT_TOPIC
        ),
    };
    let output_topic = match env::var(ENV_OUTPUT_TOPIC) {
        Ok(t) => t,
        Err(_) => bail!(
            "no output topic found in environment value {}",
            ENV_OUTPUT_TOPIC
        ),
    };

    // See if we were given an optional source format to use for handling String inputs.
    let fmt = env::var(ENV_FORMAT).map_or(None, |s| Some(s));

    // Grab a connection to the Schema Registry and check our input topic.
    let mut sr = SchemaRegistryClient::new();
    let subject = format!(
        "{}-{}",
        input_topic,
        if mode.is_key() { "key" } else { "value" }
    );
    let input_schema = match sr.lookup_latest_schema(subject.as_str()) {
        Ok(s) => s,
        Err(e) => bail!("failed to fetch schema for subject {}: {:?}", subject, e),
    };
    // Intrinsic TOCTOU, but at least see if we can confirm support early.
    let format = match input_schema.schema().format() {
        SchemaFormat::Avro => SchemaFormat::Avro,
        SchemaFormat::Json => bail!("json schema is not supported"),
        SchemaFormat::Protobuf => bail!("protobuf schema is not supported"),
    };

    // Check our output topic schema exists. If not, create it.
    let output_subject = format!(
        "{}-{}",
        output_topic,
        if mode.is_key() { "key" } else { "value" }
    );
    if sr.lookup_latest_schema(output_subject.as_str()).is_err() {
        let output_schema = match format {
            SchemaFormat::Avro => avro::convert_schema(input_schema.schema(), &mode, &target_type)?,
            SchemaFormat::Protobuf => bail!("protobuf not supported"),
            SchemaFormat::Json => bail!("json not supported"),
        };
        match sr.create_schema(output_subject.as_str(), output_schema) {
            Ok(_) => {}
            Err(e) => bail!("failed to create schema for output topic {}: {:?}",
                output_topic, e)
        }
    };

    // Should probably use specific functions from Avro, Protobuf, etc. modules.
    // For now, we just assume Avro.
    // n.b. due to the signature of `on_record_written` using Fn and not MutFn, we can't pass
    // a mutable reference to the SchemaRegistryClient
    println!("enabling timestamp conversion from {} to {} using Mode::{:?}, TargetType::{:?}, and incoming String format of {:?}",
        input_topic, output_topic, mode, target_type, fmt
    );
    on_record_written(|ev, w| {
        match avro::convert_event(ev, w, &output_topic, &mode, &target_type, &sr, fmt.as_ref()) {
            Ok(_) => {},
            Err(e) => {
                // TODO: add in logic for either DLQ, pass-through, drop, or panic. For now, drop.
                eprintln!("{:?}", e);
            }
        };
        // XXX We *must* not return Err for now as it will panic the Rust wasm runtime.
        anyhow::Ok(())
    })
}

#[cfg(test)]
mod tests {
    use crate::{Mode, Precision, TargetType};

    const GOOD_MODE_TESTS: [(&str, fn() -> Mode); 4] = [
        ("key", || Mode::Key),
        ("key[my-Cool-Key]", || {
            Mode::KeyField(String::from("my-Cool-Key"))
        }),
        ("value[myField]", || {
            Mode::ValueField(String::from("myField"))
        }),
        ("value", || Mode::Value),
    ];

    const BAD_MODE_TESTS: [&str; 4] = ["", "junk", "key[]", "value[]"];
    #[test]
    fn can_parse_good_mode() {
        for (input, expected) in GOOD_MODE_TESTS {
            println!("testing good mode: {:?}", input);
            assert_eq!(expected(), Mode::try_from(String::from(input)).unwrap());
        }
    }
    #[test]
    fn will_fail_on_bad_modes() {
        for input in BAD_MODE_TESTS {
            println!("testing bad mode: {:?}", input);
            assert!(Mode::try_from(String::from(input)).is_err());
        }
    }

    const GOOD_TARGET_TESTS: [(&str, fn() -> TargetType); 7] = [
        ("string[%Y-%m-%dT%H:%M]", || {
            TargetType::String(
                chrono::format::StrftimeItems::new("%Y-%m-%dT%H:%M")
                    .parse_to_owned()
                    .unwrap(),
            )
        }),
        ("unix[seconds]", || TargetType::Unix(Precision::Seconds)),
        ("unix[s]", || TargetType::Unix(Precision::Seconds)),
        ("unix", || TargetType::Unix(Precision::Seconds)),
        ("date", || TargetType::Date),
        ("Date", || TargetType::Date),
        ("time", || TargetType::Time),
    ];

    const BAD_TARGET_TESTS: [&str; 4] = ["", "date[]", "string[xxx]", "unix[xyz]"];

    #[test]
    fn can_parse_good_targets() {
        for (input, expected) in GOOD_TARGET_TESTS {
            println!("testing good target: {:?}", input);
            assert_eq!(
                expected(),
                TargetType::try_from(String::from(input)).unwrap()
            );
        }
    }
    #[test]
    fn will_fail_on_bad_targets() {
        for input in BAD_TARGET_TESTS {
            println!("testing bad target: {:?}", input);
            assert!(TargetType::try_from(String::from(input)).is_err());
        }
    }
}
