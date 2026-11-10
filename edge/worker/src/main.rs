use std::io::{BufRead, BufReader, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::time::Duration;

fn ping(address: &str) -> Result<(), Box<dyn std::error::Error>> {
    let target = address.to_socket_addrs()?.next().ok_or("no address")?;
    let mut stream = TcpStream::connect_timeout(&target, Duration::from_secs(2))?;
    stream.set_read_timeout(Some(Duration::from_secs(2)))?;
    stream.set_write_timeout(Some(Duration::from_secs(2)))?;
    stream.write_all(b"*1\r\n$4\r\nPING\r\n")?;
    let mut response = String::new();
    BufReader::new(stream).read_line(&mut response)?;
    if response != "+PONG\r\n" {
        return Err("unexpected Valkey response".into());
    }
    Ok(())
}

fn main() {
    let address = std::env::var("VALKEY_ADDRESS").unwrap_or_else(|_| "valkey:6379".to_owned());
    loop {
        match ping(&address) {
            Ok(()) => println!("Valkey connection healthy; job processing not implemented"),
            Err(error) => eprintln!("Valkey unavailable: {error}"),
        }
        std::thread::sleep(Duration::from_secs(30));
    }
}

