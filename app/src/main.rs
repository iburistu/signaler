#[macro_use]
extern crate rocket;
#[macro_use]
extern crate lazy_static;
use dbus::blocking::SyncConnection;
use rocket::http::Status;
use rocket::request::{FromRequest, Outcome, Request};
use rocket::serde::{json::Json, Deserialize, Serialize};
use rocket::State;
use std::env;
use std::time::Duration;

lazy_static! {
    static ref SESSION: SyncConnection = SyncConnection::new_session().unwrap();
}

struct DBusSession {
    proxy: dbus::blocking::Proxy<'static, &'static dbus::blocking::SyncConnection>,
}

struct Secret<'r>(&'r str);

#[derive(Debug)]
enum SecretError {
    Missing,
    Invalid,
}

#[rocket::async_trait]
impl<'r> FromRequest<'r> for Secret<'r> {
    type Error = SecretError;

    async fn from_request(req: &'r Request<'_>) -> Outcome<Self, Self::Error> {
        fn is_valid(key: &str) -> bool {
            key == format!("Bearer {}", env::var("SIGNALER_SECRET").unwrap())
        }

        match req.headers().get_one("Authorization") {
            None => Outcome::Failure((Status::BadRequest, SecretError::Missing)),
            Some(key) if is_valid(key) => Outcome::Success(Secret(key)),
            Some(_) => Outcome::Failure((Status::BadRequest, SecretError::Invalid)),
        }
    }
}

#[derive(Deserialize)]
#[serde(crate = "rocket::serde")]
struct IndexRequest {
    message: String,
}

#[derive(Serialize)]
#[serde(crate = "rocket::serde")]
struct IndexResponse {
    timestamp: Option<i64>,
}

#[post("/", format = "json", data = "<message>")]
fn index(
    message: Json<IndexRequest>,
    _secret: Secret<'_>,
    connection: &State<DBusSession>,
) -> Json<IndexResponse> {
    let attachments: Vec<String> = vec![];
    let (timestamp,): (i64,) = connection
        .proxy
        .method_call(
            "org.asamk.Signal",
            "sendMessage",
            (
                message.message.to_string(),
                attachments,
                env::var("SIGNAL_RECIPIENT").unwrap(),
            ),
        )
        .unwrap();
    Json(IndexResponse {
        timestamp: Some(timestamp),
    })
}

#[derive(Serialize)]
#[serde(crate = "rocket::serde")]
struct SelfResponse {
    number: Option<String>,
}

#[launch]
fn rocket() -> _ {
    rocket::build()
        .mount("/", routes![index])
        .manage(DBusSession {
            proxy: dbus::blocking::Proxy::new(
                "org.asamk.Signal",
                "/org/asamk/Signal",
                Duration::from_millis(5000),
                &SESSION,
            ),
        })
}
