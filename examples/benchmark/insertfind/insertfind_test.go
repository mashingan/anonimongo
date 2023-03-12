package main

import (
	"context"
	"log"
	"sync"
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
	client    *mongo.Client
	currtime  = time.Now()
	db        *mongo.Database
	coll      *mongo.Collection
	insertnum = 100
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

	db = client.Database("newtemptest")
	coll = db.Collection("temptest")
	coll.Drop(context.Background())
}

var res *mongo.SingleResult

func insert100FindLast() (res *mongo.SingleResult, err error) {
	ctx := context.Background()
	var wg sync.WaitGroup
	for i := 0; i < insertnum; i++ {
		wg.Add(1)
		go func(i int, w *sync.WaitGroup) {
			defer w.Done()
			_, err = coll.InsertOne(ctx, bson.M{
				"oneHundred":         i,
				"hello world":        isekai,
				"a percent of truth": 0.42,
				"array world":        []interface{}{"red", 50, 4.2},
				"this is null":       nil,
				"now":                currtime,
				//"_id": curroid
			})
		}(i, &wg)
	}
	wg.Wait()
	res = coll.FindOne(ctx, bson.M{"oneHundred": insertnum - 1})
	return
}

func BenchmarkInsert100FindLast(b *testing.B) {
	var r *mongo.SingleResult
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		r, _ = insert100FindLast()
	}
	res = r
	b.Log("res:", res)
}
