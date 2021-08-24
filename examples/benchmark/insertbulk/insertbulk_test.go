package main

import (
	"context"
	"log"
	"testing"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

const (
	maxiter = 10000
	isekai  = "hello異世界"
)

var (
	client   *mongo.Client
	docs     = make([]interface{}, maxiter)
	currtime = time.Now()
	db       *mongo.Database
	coll     *mongo.Collection
)

func init() {

	// Set client options
	clientOptions := options.Client().ApplyURI("mongodb://localhost:27017")

	// Connect to MongoDB
	var err error
	client, err = mongo.Connect(context.TODO(), clientOptions)
	if err != nil {
		log.Fatal(err)
	}

	for i := range docs {
		docs[i] = bson.M{
			"hello":              i,
			"hello world":        isekai,
			"a percent of truth": 0.42,
			"array world":        []interface{}{"red", 50, 4.2},
			"this is null":       nil,
			"now":                currtime,
			//"_id": curroid
		}
	}

	db = client.Database("newtemptest")
	coll = db.Collection("temptest")
	coll.Drop(context.Background())
}

var res *mongo.InsertManyResult

func insertManyDrop() (res *mongo.InsertManyResult, err error) {
	ctx := context.Background()
	res, err = coll.InsertMany(ctx, docs)
	coll.Drop(ctx)
	return
}

func BenchmarkInsertManyDrop(b *testing.B) {
	var r *mongo.InsertManyResult
	for i := 0; i < b.N; i++ {
		r, _ = insertManyDrop()
	}
	res = r
}
