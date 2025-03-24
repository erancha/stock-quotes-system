# Stock Quotes System Architecture

## Requirements

Please refer to the [Requirements](requirements.md) document.

## Table of Contents

<!-- toc -->

- [Solution Overview](#solution-overview)
- [Architecture Diagram](#architecture-diagram)
- [Services](#services)
  * [1. `Receiver` Service](#1-receiver-service)
  * [2. `Raw Data` Service](#2-raw-data-service)
  * [3. `Highest Value Change` Service](#3-highest-value-change-service)
  * [4. `Daily Stats` Service](#4-daily-stats-service)
  * [5. `Grafana Visualization` Service](#5-grafana-visualization-service)
- [Services drill-down](#services-drill-down)
  * [1. `Receiver` Service](#1-receiver-service-1)
    + [REST API](#rest-api)
    + [Data Validation](#data-validation)
  * [2. `Raw Data` Service](#2-raw-data-service-1)
    + [Processing](#processing)
    + [Storage](#storage)
  * [3. `Highest Value Change` Service](#3-highest-value-change-service-1)
    + [Simplified flow](#simplified-flow)
    + [Sample persisted document](#sample-persisted-document)
    + [High Availability](#high-availability)
  * [4. `Daily Stats` Service](#4-daily-stats-service-1)
    + [Simplified flow](#simplified-flow-1)
    + [Sample persisted document](#sample-persisted-document-1)
    + [High Availability](#high-availability-1)
  * [5. `Grafana Visualization` Service](#5-grafana-visualization-service-1)
    + [Dashboards](#dashboards)
    + [Alerting](#alerting)
    + [Data Sources](#data-sources)
- [Tech stack](#tech-stack)
  * [Kafka](#kafka)
  * [MongoDB](#mongodb)
- [Appendix A: `Highest Value Change` Service - implementation notes](#appendix-a-highest-value-change-service---implementation-notes)
- [License](#license)

<!-- tocstop -->

## Solution Overview

The stock quotes system is designed to process and analyze stock market data in real-time. The system:

- Ingests stock quotes through a REST API ([`Receiver` Service](#1-receiver-service))
- Stores historical quote data for deep analysis ([`Raw Data` Service](#2-raw-data-service))
- Tracks significant price changes in 30-minute windows ([`Highest Value Change` Service](#3-highest-value-change-service))
- Calculates daily statistics for all stocks ([`Daily Stats` Service](#4-daily-stats-service))
- Provides real-time monitoring and visualization ([`Grafana Visualization` Service](#5-grafana-visualization-service))
- Handles ~10,000 quotes per second

The solution uses a microservices architecture to maintain separation of concerns and enable independent evolution of each component, with [Kafka](#kafka) streaming data between services.

## Architecture Diagram

![Architecture Diagram](https://lucid.app/publicSegments/view/9d1a597d-f850-4db4-b392-c292b8febef0/image.jpeg)

## Services

### 1. `Receiver` Service

[Requirements](requirements.md): Accept and validate stock quotes

Solution:

- Load balanced REST API for ingestion
- Validates and standardizes quotes
- Publishes to Kafka
- See [drill-down](#1-receiver-service-1) for details

### 2. `Raw Data` Service

[Requirements](requirements.md): Store quote history for analysis

Solution:

- Consumes quotes from Kafka: `stock-quotes` topic
- Persists to MongoDB time-series collection for efficient historical storage
- See [drill-down](#2-raw-data-service-1) for details

### 3. `Highest Value Change` Service

[Requirements](requirements.md): Save each minute the stock symbol with highest value change in last 30 minutes

- Consumes quotes from Kafka: `stock-quotes` topic
- Detects price changes in 30-minute windows, in memory, and persists to MongoDB every 1 minute
- See [drill-down](#3-highest-value-change-service-1) for details

### 4. `Daily Stats` Service

[Requirements](requirements.md): Save daily change and min/max prices

- Consumes quotes from Kafka: `stock-quotes` topic
- Calculates and stores daily statistics, in memory, and persists to MongoDB at market close
- See [drill-down](#4-daily-stats-service-1) for details

### 5. `Grafana Visualization` Service

[Requirements](requirements.md): Visualize system data

Solution:

- Reads from MongoDB for real-time monitoring and analysis
- See [drill-down](#5-grafana-visualization-service-1) for details

## Services drill-down

### 1. `Receiver` Service

[Requirements](requirements.md): Accept and validate stock quotes

#### REST API

- Endpoint: `/api/v1/quotes`
- Method: POST
- Rate limiting: 10,000 requests/sec

#### Data Validation

- Required fields: symbol, price, timestamp
- Price validation: > 0
- Symbol validation: Alphanumeric, max 10 chars
- Example document:
  ```json
  {
    "symbol": "AAPL",
    "price": 150.25,
    "volume": 1000,
    "timestamp": ISODate("2025-03-19T14:03:43.123Z")
  }
  ```

### 2. `Raw Data` Service

[Requirements](requirements.md): Store quote history for analysis

#### Processing

- Error handling:
  - Dead letter queue for invalid data
  - Retry policy: 3 attempts
  - Exponential backoff: 1s, 2s, 4s

#### Storage

- Collection: time-series optimized
- Automatic data cleanup after 30-day retention period
- Sharding:
  - Key: symbol (even distribution of writes)
- Indexes:
  - Primary: { timestamp: 1, symbol: 1 } - For efficient time-range queries by symbol
  - Secondary: { symbol: 1, timestamp: -1 } - For latest price lookups by symbol
  - TTL: timestamp (30-day expiry)

### 3. `Highest Value Change` Service

[Requirements](requirements.md): Save each minute the stock symbol with highest value change in last 30 minutes

#### Simplified flow

```javascript
1. Initialize:
   - Create 'Kafka consumer' (group: 'stock-db-writers')
   - Initialize 'in-memory price windows' // 30-min sliding windows, one per symbol'
   - Connect to MongoDB

2. Main Processing Loop:
   while (true) {
       // Consume messages from Kafka
       messages = kafka.consume("stock-quotes")

       for each message in messages {
           // Update in-memory window
           priceWindow = getOrCreateWindow(message.symbol)
           priceWindow.add(message.price, message.timestamp) // responsible to manage high and low

           // Clean old data (> 30 minutes)
           priceWindow.cleanup()
       }

       // Every minute
       if (isMinuteInterval()) {
           sort the 'in-memory price windows' by 'valueChange' in descending order {
               // Calculate value change
               window = getWindow(symbol)
               'valueChange' = ((window.high - window.low) / window.low) * 100
           }

           // Persist to MongoDB the N symbols with highest 'valueChange'
           mongodb.insert({
                timestamp: currentTime,
                symbol: symbol,
                valueChange: 'valueChange',
                startPrice: window.startPrice,
                endPrice: window.currentPrice,
                windowStart: window.startTime,
                windowEnd: window.endTime
           })
       }
   }

3. Error Handling:
   try {
       // Main processing loop
   } catch (error) {
       // Retry up to 3 times
       // If still failing, send to dead letter queue
   }
```

#### Sample persisted document

```json
{
  "timestamp": ISODate("2025-03-19T14:03:00.000Z"),
  "symbol": "AAPL",
  "valueChange": 2.5%,
  "startPrice": 150.25,
  "endPrice": 154.00,
  "windowStart": ISODate("2025-03-19T13:33:00.000Z"),
  "windowEnd": ISODate("2025-03-19T14:03:00.000Z")
}
```

- Refer to [Appendix A: `Highest Value Change` Service - Implementation](#appendix-a-highest-value-change-service---implementation)

#### High Availability

- Active-standby deployment:
  - 2 nodes minimum
  - Automatic failover via leader election
  - Kafka consumer group rebalancing
- Recovery strategy:
  - Resume from last committed Kafka offset
  - Rebuild 30-min window from Kafka history

### 4. `Daily Stats` Service

[Requirements](requirements.md): Save daily change and min/max prices

#### Simplified flow

```javascript
// For each quote received from Kafka
processQuote(quote) {
  const stats = dailyStats.get(quote.symbol) || createNewDayStats(quote.symbol)

  // Update running calculations
  if (isMarketOpen()) {
    if (!stats.openPrice) stats.openPrice = quote.price  // First quote of day
    stats.highPrice = Math.max(stats.highPrice, quote.price)
    stats.lowPrice = Math.min(stats.lowPrice, quote.price)
    stats.volume += quote.volume
    stats.vwapNumerator += quote.price * quote.volume  // For VWAP calculation
  }
}

// Triggered by market close event
async onMarketClose() {
  const batchSize = 1000
  for (const symbolBatch of getBatches(dailyStats.keys(), batchSize)) {
    await Promise.all(symbolBatch.map(async symbol => {
      const stats = dailyStats.get(symbol)
      stats.closePrice = getLastPrice(symbol)
      stats.vwap = stats.vwapNumerator / stats.volume

      // Persist to MongoDB
      await persistDailyStats(stats)
    }))
  }
}
```

#### Sample persisted document

```json
{
  "date": ISODate("2025-03-19"),
  "symbol": "AAPL",
  "openPrice": 150.25,
  "highPrice": 155.00,
  "lowPrice": 149.50,
  "closePrice": 154.00,
  "vwap": 152.75,
  "volume": 1000000,
  "valueChangePercent": 2.5,
  "movingAverages": {
    "5day": 151.20,
    "20day": 148.75
  }
}
```

#### High Availability

The service uses an active-active deployment model:

1. Partition Assignment:

```javascript
// Each instance gets assigned specific symbols via Kafka consumer group
onPartitionsAssigned(partitions) {
  // Clear existing state for reassigned partitions
  for (const partition of partitions) {
    const symbols = getSymbolsForPartition(partition)
    symbols.forEach(symbol => {
      dailyStats.set(symbol, loadLatestStats(symbol))
    })
  }
}
```

2. Recovery Flow:

```javascript
// On instance startup or failover
async recoverState() {
  // Get assigned symbols from Kafka consumer group
  const symbols = getAssignedSymbols()

  // Rebuild state from MongoDB and Kafka
  for (const symbol of symbols) {
    const stats = await loadLatestStats(symbol)
    const recentQuotes = await getRecentQuotes(symbol)
    recentQuotes.forEach(quote => processQuote(quote))
  }
}
```

### 5. `Grafana Visualization` Service

#### Dashboards

- Real-time monitoring:
  - Current stock prices and volumes
  - Highest value changes (30-min window)
  - Daily statistics
- Market status:
  - Opening/closing detection
  - Trading halts
  - Holiday calendar

#### Alerting

- Market events:
  - Unusual price movements
  - Trading halts
  - Market open/close

#### Data Sources

- MongoDB collections:
  - Raw quotes (30-day history)
  - Highest value changes (90-day history)
  - Daily statistics (365-day history)

## Tech stack

### Kafka

- Central message broker for decoupling
- Partitioned by stock symbol for parallel processing
- Replicated for fault tolerance

1. Configuration

- 3 brokers for redundancy
- 3 partitions for parallel processing
- Replication factor: 3
- Message retention: 30 days

2. Performance

- Throughput: ~100 MB/sec
- Latency: < 10ms
- Disk usage: ~1 TB

3. Monitoring

- Kafka metrics monitoring
- Broker health checks
- Partition leader election monitoring

### MongoDB

The decision to use MongoDB over PostgreSQL was driven by our system's specific performance requirements:

1. Real-Time Window Calculations (Critical)

   - Requirement: Process 30-minute sliding windows with < 2 second query latency
   - MongoDB Solution:
     - Native time-series collections with automatic time-based chunking
     - Optimized storage format for sequential time-based reads
     - Built-in window functions in aggregation pipeline
   - PostgreSQL Alternative:
     - Would need manual time-based partitioning
     - Complex materialized views requiring frequent updates
     - Window functions potentially slower on high-volume data

2. High-Volume Write Performance (Critical)

   - Requirement: Ingest 10,000 quotes/sec (~15 MB/min) with < 50ms latency
   - MongoDB Solution:
     - Automatic sharding by symbol for parallel writes
     - Optimized batch processing with w1 write concern
     - No schema validation overhead
   - PostgreSQL Alternative:
     - Manual table partitioning needed
     - Write-ahead logging impacts write speed
     - Schema validation on every insert

3. Data Lifecycle Management

   - Requirements:
     - Raw quotes: 30 days, 648 GB
     - Value changes: 90 days, 2.6 MB
     - Daily stats: 365 days, 19 MB
   - MongoDB Solution:
     - TTL indexes for automatic expiration
     - Different write/read patterns per collection
     - Efficient time-based data pruning
   - PostgreSQL Alternative:
     - Custom cleanup jobs needed
     - Manual partition rotation
     - More complex backup strategy

MongoDB's native time-series capabilities provide these features out-of-the-box, significantly reducing both development effort and operational complexity compared to implementing equivalent functionality in PostgreSQL.

## Appendix A: `Highest Value Change` Service - implementation notes

For managing highest and lowest values within a 30-minute sliding window, a heap would be overkill and less efficient than simpler alternatives. Here's why:

For just tracking high/low values, we only need to know two things:

- The maximum and minimum values
- When each price occurred (to handle the 30-minute window expiration)

A more efficient data structure would be a sorted linked list or a circular buffer with the following properties:

**python**:

```python
class PricePoint:
    price: float
    timestamp: datetime

class PriceWindow:
    prices: CircularBuffer[PricePoint]  # Fixed size, O(1) insertion
    currentHigh: PricePoint  # Tracks current highest price point
    currentLow: PricePoint   # Tracks current lowest price point

    def add(price, timestamp):
        # O(1) operations
        new_point = PricePoint(price, timestamp)
        self.prices.append(new_point)

        # Update high/low if needed
        if price > self.currentHigh.price:
            self.currentHigh = new_point
        if price < self.currentLow.price:
            self.currentLow = new_point

        # If we evicted an old price that was our high/low,
        # scan buffer to find new high/low - O(n) but happens rarely
        if self.prices.did_evict_point():
            if self.prices.evicted_point == self.currentHigh:
                self.recalculate_high()
            if self.prices.evicted_point == self.currentLow:
                self.recalculate_low()
```

**javascript**:

```javascript
class PricePoint {
  constructor(price, timestamp) {
    this.price = price;
    this.timestamp = timestamp;
  }
}

class CircularBuffer {
  constructor(maxSize) {
    this.buffer = new Array(maxSize);
    this.head = 0;
    this.tail = 0;
    this.size = 0;
    this.maxSize = maxSize;
    this.lastEvictedPoint = null;
  }

  append(item) {
    if (this.size === this.maxSize) {
      this.lastEvictedPoint = this.buffer[this.head];
      this.head = (this.head + 1) % this.maxSize;
      this.size--;
    }
    this.buffer[this.tail] = item;
    this.tail = (this.tail + 1) % this.maxSize;
    this.size++;
  }

  didEvictPoint() {
    return this.lastEvictedPoint !== null;
  }

  get evictedPoint() {
    return this.lastEvictedPoint;
  }

  *[Symbol.iterator]() {
    let current = this.head;
    let count = 0;
    while (count < this.size) {
      yield this.buffer[current];
      current = (current + 1) % this.maxSize;
      count++;
    }
  }
}

class PriceWindow {
  constructor(windowSizeMinutes = 30) {
    // Assuming 1 price update per second on average
    const maxSize = windowSizeMinutes * 60;
    this.prices = new CircularBuffer(maxSize);
    this.currentHigh = null;
    this.currentLow = null;
  }

  add(price, timestamp) {
    const newPoint = new PricePoint(price, timestamp);
    this.prices.append(newPoint);

    // Update high/low if needed
    if (!this.currentHigh || price > this.currentHigh.price) {
      this.currentHigh = newPoint;
    }
    if (!this.currentLow || price < this.currentLow.price) {
      this.currentLow = newPoint;
    }

    // If we evicted an old price that was our high/low,
    // scan buffer to find new high/low - O(n) but happens rarely
    if (this.prices.didEvictPoint()) {
      const evictedPoint = this.prices.evictedPoint;
      if (evictedPoint === this.currentHigh) {
        this.recalculateHigh();
      }
      if (evictedPoint === this.currentLow) {
        this.recalculateLow();
      }
    }
  }

  recalculateHigh() {
    this.currentHigh = Array.from(this.prices).reduce((max, point) => (!max || point.price > max.price ? point : max), null);
  }

  recalculateLow() {
    this.currentLow = Array.from(this.prices).reduce((min, point) => (!min || point.price < min.price ? point : min), null);
  }

  getValueChange() {
    if (!this.currentHigh || !this.currentLow) return 0;
    return ((this.currentHigh.price - this.currentLow.price) / this.currentLow.price) * 100;
  }
}
```

Why this is better than a heap:

1. **Time Complexity**:

   - Heap: O(log n) for every insertion
   - Circular Buffer with tracking: O(1) for most operations, O(n) only when high/low expires

2. **Memory Efficiency**:

   - Heap: Would need two heaps (min and max) to track both high and low
   - Circular Buffer: Single structure with fixed size based on time window

3. **Window Management**:

   - Heap: Complex to remove expired values, would need additional index
   - Circular Buffer: Naturally expires old values, perfect for time-based window

4. **Access Speed**:
   - Heap: O(1) for getting min/max but O(log n) for updates
   - Our Solution: O(1) for everything except rare recalculation cases

The key insight is that we don't need sorted access to all prices - we only need the extremes, and those change relatively infrequently. When they do change, it's either because:

1. A new price is higher/lower (O(1) to update)
2. The current high/low expired (O(n) to recalculate, but happens only once per expiration)

This approach is particularly efficient for high-frequency trading data where you're getting many updates per second but only need to track the extremes within the window.

## License

This project is licensed under the Creative Commons Attribution-NonCommercial 4.0 International License. You can view the full license [here](https://creativecommons.org/licenses/by-nc/4.0/).

```

```
