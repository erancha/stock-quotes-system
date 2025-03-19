# Requirements

## Functional Requirements

- Save all quotes to storage.
- Save each minute the stock symbol with highest value change in last 30 minutes.
- Save daily change and min/max prices of each stock.
- Provide history graphs of stock changes.

## Non-Functional Requirements

### Processing Requirements
- Processing capacity: ~10,000 quotes/sec (~600,000 quotes/min)

### Data Requirements
For detailed data model and storage implementation, see [Storage section in readme.md](readme.md#storage).

- Raw quotes:
  * Size: ~25 B/event, ~15 MB/min
  * Retention: 30 days (~648 GB total)
- Highest value changes:
  * Size: ~20 B/min
  * Retention: 90 days (~2.6 MB total)
- Daily statistics:
  * Size: ~52 KB/day (1000 symbols)
  * Retention: 365 days (~19 MB total)

### Performance Requirements
- User-facing response times:
  * Quote ingestion: < 100ms
  * Data queries: < 2 seconds
- Background processing:
  * Highest value changes: Updated every minute
  * Daily statistics: Updated within 5 minutes of market close

### Availability Requirements
- Service uptime: 99.99%
- No data loss for committed transactions
- Automatic failover < 10 seconds
- No single point of failure
