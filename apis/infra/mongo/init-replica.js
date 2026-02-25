// MongoDB replica set initialisation
// This script runs once when the MongoDB container first starts
rs.initiate({
    _id: "rs0",
    members: [{ _id: 0, host: "mongo:27017" }]
});

// Wait for primary election
sleep(2000);

// Create application database user with minimal required privileges
db.getSiblingDB("gamehub").createUser({
    user: "gamehub_app",
    pwd: process.env.MONGO_APP_PASSWORD || "change_in_production",
    roles: [
        { role: "readWrite", db: "gamehub" }
    ]
});
