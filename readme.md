# Stock Quotes System Architecture

## Requirements

Please refer to the [Requirements](requirements.md) document.

## Solution Overview

This stock quotes system is designed to process and analyze stock market data in real-time, with a focus on high throughput (~10,000 quotes/sec) and efficient data storage. The system follows a microservices architecture pattern using Kafka as the central message broker.

## Architecture Diagram

![Architecture Diagram](https://lucid.app/publicSegments/view/9d1a597d-f850-4db4-b392-c292b8febef0/image.jpeg)

## Table of Contents

<!-- toc -->

- [Components](#components)
  * [1. Receiver Service](#1-receiver-service)
  * [2. Kafka Cluster](#2-kafka-cluster)
  * [3. Consumer Services](#3-consumer-services)
    + [Raw Data Consumer](#raw-data-consumer)
    + [Highest Value Change Service](#highest-value-change-service)
    + [Daily Stats Service](#daily-stats-service)
  * [4. Grafana Visualization Service](#4-grafana-visualization-service)
- [Data Flow](#data-flow)
- [Storage](#storage)
  * [Why MongoDB?](#why-mongodb)
- [Scalability Considerations](#scalability-considerations)
- [Services drill-down](#services-drill-down)
  * [1. Receiver Service](#1-receiver-service-1)
    + [REST API](#rest-api)
    + [Data Validation](#data-validation)
    + [Kafka Production](#kafka-production)
  * [2. Raw Data Consumer](#2-raw-data-consumer)
    + [Processing](#processing)
    + [Storage](#storage-1)
  * [3. Highest Value Change Service](#3-highest-value-change-service)
    + [Window Processing](#window-processing)
    + [Value Change Calculation](#value-change-calculation)
    + [Performance Optimization](#performance-optimization)
  * [4. Daily Stats Service](#4-daily-stats-service)
    + [Daily Calculations](#daily-calculations)
    + [Data Management](#data-management)
    + [Monitoring](#monitoring)
  * [5. Grafana Visualization Service](#5-grafana-visualization-service)
    + [Dashboards](#dashboards)
    + [Alerting](#alerting)
    + [Data Sources](#data-sources)
    + [Access Control](#access-control)

<!-- tocstop -->

## Components

### [1. Receiver Service](#1-receiver-service-1)

- Provides REST API endpoint for receiving stock quotes from external sources
- Validates incoming quote data for integrity and format
- Acts as a Kafka producer, publishing validated quotes to the Kafka cluster

### 2. Kafka Cluster

- Central message broker with the `stock-quotes` topic
- Configured with 3 partitions for parallel processing
- Enables decoupling of data ingestion from processing
- Supports multiple consumer groups for different use cases

### 3. Consumer Services

#### [Raw Data Consumer](#2-raw-data-consumer) (Consumer Group: stock-db-writers)

- Stores all incoming quotes in the Raw Quotes Database
- Performs data transformation if needed
- Provides historical data storage for analysis

#### [Highest Value Change Service](#3-highest-value-change-service) (Consumer Group: highest-value-change)

- Maintains a 30-minute sliding window of stock prices
- Calculates value changes within the window
- Records the stock with the highest value change every minute
- Stores results in the Highest Value Change DB

#### [Daily Stats Service](#4-daily-stats-service) (Consumer Group: daily-stats-tracker)

- Tracks daily statistics for each stock
- Calculates and stores:
  - Daily price changes
  - Minimum prices
  - Maximum prices
- Persists data in the Daily Stats Database

### [4. Grafana Visualization Service](#5-grafana-visualization-service)

- Connects to all three databases for comprehensive data visualization
- Provides customizable dashboards for different metrics
- Supports alerting capabilities for monitoring thresholds
- Enables creation of historical graphs for stock changes

## Data Flow

1. External sources send stock quotes to the [Receiver Service](#1-receiver-service-1)
2. Receiver Service validates and publishes to Kafka
3. Three consumer services process the data:
   - [Raw Data Consumer](#2-raw-data-consumer) stores all quotes
   - [Highest Value Change Service](#3-highest-value-change-service) calculates 30-minute changes
   - [Daily Stats Service](#4-daily-stats-service) maintains daily statistics
4. [Grafana Service](#5-grafana-visualization-service) visualizes data from all databases

## Storage

The system uses [MongoDB](https://www.mongodb.com/) as the primary database for all storage needs. Here's how each collection is structured and why [MongoDB](#why-mongodb) is suitable:

1. Raw Quotes Collection:
   - Stores all quote data (~15 MB/min)
   - [MongoDB's](#why-mongodb) time-series collections (introduced in version 5.0) are optimized for time-based data
   - Built-in support for data expiration with TTL indexes
   - Efficient range-based queries for historical data
   - Example document:
     ```json
     {
       "timestamp": ISODate("2025-03-19T14:03:43.123Z"),
       "symbol": "AAPL",
       "price": 150.25,
       "volume": 1000
     }
     ```
   - Implementation details in [Raw Data Consumer](#2-raw-data-consumer)

2. Highest Value Change Collection:
   - Uses [MongoDB's](#why-mongodb) aggregation pipeline for sliding window calculations
   - Stores 30-minute value changes for each symbol
   - Example document:
     ```json
     {
       "timestamp": ISODate("2025-03-19T14:03:00.000Z"),
       "symbol": "AAPL",
       "valueChange": 2.5,
       "startPrice": 150.25,
       "endPrice": 154.00,
       "windowStart": ISODate("2025-03-19T13:33:00.000Z"),
       "windowEnd": ISODate("2025-03-19T14:03:00.000Z")
     }
     ```
   - Implementation details in [Highest Value Change Service](#3-highest-value-change-service)

3. Daily Stats Collection:
   - Uses [MongoDB's](#why-mongodb) atomic operations for reliable updates
   - Maintains daily statistics with VWAP calculations
   - Example document:
     ```json
     {
       "date": ISODate("2025-03-19"),
       "symbol": "AAPL",
       "openPrice": 150.25,
       "highPrice": 155.00,
       "lowPrice": 149.50,
       "closePrice": 154.00,
       "vwap": 152.75,
       "volume": 1000000
     }
     ```
   - Implementation details in [Daily Stats Service](#4-daily-stats-service)

### Why MongoDB?

MongoDB was chosen as the primary database for several reasons:

1. Time-series Support
   - [Native time-series collections](https://www.mongodb.com/docs/manual/core/timeseries-collections/)
   - [Efficient range-based queries](https://www.mongodb.com/docs/manual/tutorial/model-time-series-data/)
   - [Automatic data expiration](https://www.mongodb.com/docs/manual/tutorial/expire-data/)

2. Aggregation Framework
   - [Powerful pipeline operations](https://www.mongodb.com/docs/manual/core/aggregation-pipeline/)
   - [Real-time analytics](https://www.mongodb.com/docs/manual/aggregation/)
   - [Window functions](https://www.mongodb.com/docs/manual/core/aggregation-pipeline-windows/)

3. Performance Optimization
   - Index Creation:
     ```javascript
     // Raw Quotes Collection indexes
     db.rawQuotes.createIndex({ "timestamp": 1, "symbol": 1 });  // For time-range queries
     db.rawQuotes.createIndex({ "symbol": 1, "timestamp": -1 }); // For latest price lookups
     
     // Highest Value Change Collection indexes
     db.valueChanges.createIndex({ 
       "timestamp": 1,
       "symbol": 1,
       "valueChange": -1
     });
     
     // Daily Stats Collection indexes
     db.dailyStats.createIndex({ 
       "date": 1,
       "symbol": 1
     });
     ```
   - [Query Optimization](https://www.mongodb.com/docs/manual/core/query-optimization/):
     ```javascript
     // Covered query example (uses only indexed fields)
     db.rawQuotes.find(
       { 
         symbol: "AAPL",
         timestamp: { 
           $gte: ISODate("2025-03-19T00:00:00Z")
         }
       },
       { _id: 0, symbol: 1, price: 1 }
     ).hint({ symbol: 1, timestamp: -1 });
     ```
   - [Aggregation Hints](https://www.mongodb.com/docs/manual/reference/operator/meta/hint/):
     ```javascript
     db.rawQuotes.aggregate([
       {
         $match: {
           timestamp: {
             $gte: new Date(Date.now() - 30 * 60 * 1000)
           }
         }
       }
     ], {
       hint: { timestamp: 1, symbol: 1 }
     });
     ```

4. Scalability Features
   - [Horizontal sharding](https://www.mongodb.com/docs/manual/sharding/)
   - [Replica sets](https://www.mongodb.com/docs/manual/replication/)
   - [Read preferences](https://www.mongodb.com/docs/manual/core/read-preference/)
   - [Write concerns](https://www.mongodb.com/docs/manual/reference/write-concern/)

## Scalability Considerations

- Kafka partitioning enables parallel processing
- Separate consumer groups allow independent scaling
- Each service can be scaled horizontally based on load
- Data processing is distributed across multiple services
- [MongoDB](#why-mongodb) horizontal scaling through:
  - Sharding for data distribution
  - Replica sets for high availability
  - Read operations from secondary nodes
  - Write concern configuration for consistency

## Services drill-down

### 1. Receiver Service

The Receiver Service is the entry point for all stock quote data. It implements:

#### REST API

- Endpoint: `/api/v1/quotes`
- Method: POST
- Rate limiting: Configurable per client
- Input validation:
  ```json
  {
    "symbol": "string",
    "price": "number",
    "volume": "number",
    "timestamp": "ISO8601"
  }
  ```

#### Data Validation

- Symbol format validation
- Price range checks
- Volume non-negative validation
- Timestamp freshness check (reject stale data)
- Schema validation

#### Kafka Production

- Topic: `stock-quotes`
- Partitioning strategy: By stock symbol
- Message format:
  ```json
  {
    "symbol": "AAPL",
    "price": 150.25,
    "volume": 1000,
    "timestamp": "2025-03-19T14:03:43.123Z",
    "receivedAt": "2025-03-19T14:03:43.125Z",
    "validationStatus": "PASSED"
  }
  ```

### 2. Raw Data Consumer

The Raw Data Consumer is responsible for persisting all valid stock quotes:

#### Processing

- Subscribes to `stock-quotes` topic
- Consumer group: `stock-db-writers`
- Batch processing for improved throughput
- Data transformation if needed (e.g., unit conversions)

#### Storage

- Uses [MongoDB](#why-mongodb) time-series collection
- Implements retry mechanism for failed writes
- Monitors write performance
- Implements data retention policies

### 3. Highest Value Change Service

The Highest Value Change Service tracks price movements:

#### Window Processing

- Maintains 30-minute sliding windows
- Updates every minute
- Uses [MongoDB's](#why-mongodb) aggregation pipeline
- Handles out-of-order data within configurable bounds

Example aggregation pipeline for highest value change:
```javascript
db.rawQuotes.aggregate([
  // Match documents within the last 30 minutes
  {
    $match: {
      timestamp: {
        $gte: new Date(Date.now() - 30 * 60 * 1000),
        $lte: new Date()
      }
    }
  },
  // Group by symbol and calculate min/max prices
  {
    $group: {
      _id: "$symbol",
      maxPrice: { $max: "$price" },
      minPrice: { $min: "$price" },
      latestPrice: { $last: "$price" },
      firstPrice: { $first: "$price" }
    }
  },
  // Calculate value change
  {
    $project: {
      symbol: "$_id",
      valueChange: {
        $multiply: [
          {
            $divide: [
              { $subtract: ["$latestPrice", "$firstPrice"] },
              "$firstPrice"
            ]
          },
          100
        ]
      },
      priceRange: { $subtract: ["$maxPrice", "$minPrice"] }
    }
  },
  // Sort by absolute value change
  {
    $sort: { valueChange: -1 }
  },
  // Get the top change
  {
    $limit: 1
  }
]);
```

#### Value Change Calculation
```javascript
valueChange = ((currentPrice - previousPrice) / previousPrice) * 100;
```

#### Performance Optimization

- In-memory caching of recent data
- Indexed queries for historical data
- Parallel processing of different symbols

### 4. Daily Stats Service

The Daily Stats Service maintains daily statistics:

#### Daily Calculations

- Opening price (first quote of the day)
- Closing price (last quote)
- High/Low prices
- Volume weighted average price (VWAP)
- Total trading volume

Example aggregation pipeline for daily statistics:
```javascript
db.rawQuotes.aggregate([
  // Match documents for today
  {
    $match: {
      timestamp: {
        $gte: new Date(new Date().setHours(0, 0, 0, 0)),
        $lt: new Date(new Date().setHours(23, 59, 59, 999))
      }
    }
  },
  // Group by symbol
  {
    $group: {
      _id: "$symbol",
      openPrice: { $first: "$price" },
      closePrice: { $last: "$price" },
      highPrice: { $max: "$price" },
      lowPrice: { $min: "$price" },
      totalVolume: { $sum: "$volume" },
      // Calculate VWAP
      volumeTimesPrice: {
        $sum: { $multiply: ["$price", "$volume"] }
      }
    }
  },
  // Calculate final statistics
  {
    $project: {
      symbol: "$_id",
      openPrice: 1,
      closePrice: 1,
      highPrice: 1,
      lowPrice: 1,
      totalVolume: 1,
      vwap: {
        $divide: ["$volumeTimesPrice", "$totalVolume"]
      },
      priceChange: {
        $subtract: ["$closePrice", "$openPrice"]
      },
      percentageChange: {
        $multiply: [
          {
            $divide: [
              { $subtract: ["$closePrice", "$openPrice"] },
              "$openPrice"
            ]
          },
          100
        ]
      }
    }
  }
]);
```

#### Data Management

- Automatic day boundary handling using [MongoDB's](#why-mongodb) date operations
- End-of-day calculations using aggregation pipeline
- Historical data archival using [MongoDB's](#why-mongodb) time-based features
- Data correction handling with atomic operations

#### Monitoring

- Data quality metrics
- Processing latency
- Coverage verification
- Alert on missing data

### 5. Grafana Visualization Service

The Grafana service provides comprehensive visualization and monitoring capabilities:

#### Dashboards

- Real-time Stock Prices
  - Current prices
  - Volume indicators
  - Price trends
- 30-Minute Analysis
  - Highest value changes
  - Moving averages
  - Volatility indicators
- Daily Statistics
  - OHLC (Open/High/Low/Close) charts
  - Volume analysis
  - Daily performance metrics

#### Alerting

- Price threshold alerts
- Volume spike detection
- Data quality warnings
- System health monitoring
  - Service latency
  - Processing delays
  - Data gaps

#### Data Sources

- [MongoDB](#why-mongodb) connections
  - Raw quotes collection
  - Highest value changes
  - Daily statistics
- Query optimization
  - Caching strategies
  - Time-based filtering
  - Aggregation at source

#### Access Control

- Role-based access
- Dashboard sharing
- API token management
- Audit logging
