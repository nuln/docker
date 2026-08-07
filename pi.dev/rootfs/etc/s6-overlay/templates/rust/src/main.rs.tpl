use axum::{routing::get, Json, Router};
use serde_json::{json, Value};
use std::net::SocketAddr;

#[tokio::main]
async fn main() {
    let app = Router::new()
        .route("/", get(root))
        .route("/health", get(health));

    let addr = SocketAddr::from(([0, 0, 0, 0], 8080));
    println!("{{ PROJECT }} listening on {addr}");
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

async fn root() -> String {
    "Hello from {{ PROJECT }}!\n".into()
}

async fn health() -> Json<Value> {
    Json(json!({ "app": "{{ PROJECT }}", "status": "ok" }))
}