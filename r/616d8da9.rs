use bitcoin::{Network, bip32::Fingerprint};
use clap::{Parser, Subcommand, error::ErrorKind};
use serde::{Serialize, Serializer};
