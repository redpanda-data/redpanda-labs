.PHONY: help start stop restart logs status setup demo-start demo-stop check monitor-lag verify verify-continuous-schema clean

help:
	@echo "Redpanda Migrator Demo - Available Commands:"
	@echo ""
	@echo "  make start          - Start all containers"
	@echo "  make stop           - Stop all containers"
	@echo "  make restart        - Restart all containers"
	@echo "  make logs           - Show logs from all containers"
	@echo "  make status         - Show status of all containers"
	@echo ""
	@echo "  make setup          - Create topics and setup migration"
	@echo "  make demo-start     - Start continuous data production (background)"
	@echo "  make demo-stop      - Stop continuous data production"
	@echo "  make check          - Check migration status (one-time)"
	@echo "  make monitor-lag    - Continuously monitor migration lag (Ctrl+C to exit)"
	@echo "  make verify         - Verify data consistency between clusters"
	@echo "  make verify-continuous-schema - Verify continuous schema syncing"
	@echo ""
	@echo "  make clean          - Stop and remove all containers and volumes"
	@echo ""
	@echo "Workflow (continuous replication):"
	@echo "  1. make start"
	@echo "  2. make setup"
	@echo "  3. make demo-start               (start continuous production)"
	@echo "  4. make verify-continuous-schema (test schema syncing)"
	@echo "  5. make monitor-lag              (watch lag in real-time, Ctrl+C to exit)"
	@echo "  6. make demo-stop                (stop when done)"
	@echo ""
	@echo "Web UIs:"
	@echo "  Source Console:   http://localhost:8080"
	@echo "  Target Console:   http://localhost:8081"
	@echo "  Migrator Metrics: http://localhost:4195/metrics"

start:
	@echo "Starting Redpanda Migrator Demo..."
	docker compose up -d
	@echo ""
	@echo "Waiting for clusters to be healthy..."
	@sleep 5
	@echo ""
	@echo "✅ Demo started!"
	@echo ""
	@echo "🌐 Source Console:    http://localhost:8080"
	@echo "🌐 Target Console:    http://localhost:8081"
	@echo "📊 Migrator Metrics:  http://localhost:4195/metrics"
	@echo ""
	@echo "📌 Next step: Create topics and setup migration"
	@echo "   Run: make setup"

stop:
	@echo "Stopping all containers..."
	docker compose stop

restart:
	@echo "Restarting all containers..."
	docker compose restart

logs:
	@echo "Showing logs (Ctrl+C to exit)..."
	docker compose logs -f

status:
	@echo "Container Status:"
	@docker compose ps

setup:
	@echo "Setting up demo environment..."
	@echo ""
	@echo "📝 Creating topics in source cluster..."
	@docker compose exec rpk-client /scripts/setup.sh
	@echo ""
	@echo "✅ Setup complete!"
	@echo ""
	@echo "Topics created in source:"
	@docker compose exec rpk-client rpk topic list --brokers redpanda-source:9092 | grep demo || true
	@echo ""
	@echo "📌 Next step: Start continuous data production"
	@echo "   Run: make demo-start"

demo-start:
	@echo "🚀 Starting continuous data production..."
	@echo ""
	@if docker compose exec rpk-client test -f /tmp/continuous-produce.pid 2>/dev/null; then \
		echo "⚠️  Continuous production is already running!"; \
		echo "   Run 'make demo-stop' to stop it first."; \
		exit 1; \
	fi
	@docker compose exec -d rpk-client /scripts/continuous-produce.sh
	@sleep 2
	@if docker compose exec rpk-client test -f /tmp/continuous-produce.pid 2>/dev/null; then \
		echo "✅ Continuous production started!"; \
		echo ""; \
		echo "📊 Messages are being produced every 2 seconds"; \
		echo "   - demo-orders: 50 msg/batch"; \
		echo "   - demo-user-state: 10 msg/batch"; \
		echo "   - demo-events: 16 msg/batch"; \
		echo "   - demo-alerts: 5 msg/batch"; \
		echo ""; \
		echo "📌 Next step: Verify continuous schema syncing"; \
		echo "   Run: make verify-continuous-schema"; \
		echo ""; \
		echo "💡 Tip: Open another terminal and run 'make monitor-lag' to watch"; \
		echo "   the migrator keep up with the continuous data stream."; \
	else \
		echo "❌ Failed to start continuous production"; \
		exit 1; \
	fi

demo-stop:
	@echo "🛑 Stopping continuous data production..."
	@if docker compose exec rpk-client test -f /tmp/continuous-produce.pid 2>/dev/null; then \
		docker compose exec rpk-client sh -c 'kill $$(cat /tmp/continuous-produce.pid) 2>/dev/null || true'; \
		sleep 1; \
		echo "✅ Continuous production stopped!"; \
	else \
		echo "ℹ️  Continuous production is not running"; \
	fi

check:
	@echo "📊 Migration Status"
	@echo "===================="
	@echo ""
	@echo "Source cluster topics:"
	@docker compose exec rpk-client rpk topic list --brokers redpanda-source:9092 | grep "demo-" || echo "  No demo topics found"
	@echo ""
	@echo "Target cluster topics:"
	@docker compose exec rpk-client rpk topic list --brokers redpanda-target:9092 | grep "demo-" || echo "  No demo topics found (migration may be in progress)"
	@echo ""
	@echo "Migration lag per topic:"
	@curl -s http://localhost:4195/metrics 2>/dev/null | grep "^redpanda_lag.*demo-" | awk -F'[,}]' '{ for(i=1;i<=NF;i++) if($$i ~ /topic=/) {gsub(/.*topic="/,"",$$i); gsub(/"/,"",$$i); topic=$$i} } {lag[topic]+=$$NF} END {for(t in lag) printf "  %s: %.0f\n", t, lag[t]}' | sort
	@echo ""
	@echo "Detailed metrics: http://localhost:4195/metrics"
	@echo ""
	@echo "📌 Next step: Monitor lag in real-time"
	@echo "   Run: make monitor-lag"
	@echo ""
	@echo "💡 Note: Schemas are automatically synced every 10 seconds"

monitor-lag:
	@echo "📊 Monitoring Migration Lag (refreshing every 2s)"
	@echo "Press Ctrl+C to stop"
	@echo ""
	@while true; do \
		clear; \
		echo "📊 Migration Lag Monitor - $$(date '+%H:%M:%S')"; \
		echo "========================================="; \
		echo ""; \
		echo "Lag per topic:"; \
		curl -s http://localhost:4195/metrics 2>/dev/null | grep "^redpanda_lag.*demo-" | awk -F'[,}]' '{ for(i=1;i<=NF;i++) if($$i ~ /topic=/) {gsub(/.*topic="/,"",$$i); gsub(/"/,"",$$i); topic=$$i} } {lag[topic]+=$$NF} END {for(t in lag) printf "  %-25s %.0f\n", t":", lag[t]}' | sort || echo "  No lag data available"; \
		echo ""; \
		echo "Total messages in source:"; \
		docker compose exec rpk-client sh -c 'for topic in demo-orders demo-user-state demo-events demo-alerts; do count=$$(rpk topic describe $$topic -p --brokers redpanda-source:9092 2>/dev/null | tail -n +2 | awk "{sum += \$$6} END {print sum+0}"); printf "  %-25s %s\n" "$$topic:" "$$count"; done' 2>/dev/null || echo "  Unable to fetch"; \
		echo ""; \
		echo "Continuous production status:"; \
		if docker compose exec rpk-client test -f /tmp/continuous-produce.pid 2>/dev/null; then \
			echo "  🟢 Running"; \
		else \
			echo "  🔴 Stopped"; \
		fi; \
		echo ""; \
		echo "Press Ctrl+C to stop monitoring"; \
		sleep 2; \
	done

verify:
	@echo "🔍 Verifying Data Consistency"
	@echo "=============================="
	@docker compose exec rpk-client /scripts/verify.sh
	@echo ""
	@echo "📌 Verification complete!"
	@echo ""
	@echo "💡 When done with the demo:"
	@echo "   make demo-stop - Stop continuous production"
	@echo ""
	@echo "⚠️  Important: Disable Schema Registry import mode"
	@echo "   curl -X PUT http://localhost:28081/mode \\"
	@echo "     -H 'Content-Type: application/json' \\"
	@echo "     -d '{\"mode\":\"READWRITE\"}'"
	@echo ""
	@echo "🌐 View clusters in consoles:"
	@echo "   Source: http://localhost:8080"
	@echo "   Target: http://localhost:8081"

verify-continuous-schema:
	@echo "🔬 Testing Continuous Schema Syncing"
	@echo "====================================="
	@echo ""
	@docker compose exec rpk-client /scripts/verify-continuous-schema.sh
	@echo ""
	@echo "📌 Next step: Monitor lag in real-time"
	@echo "   Run: make monitor-lag"

clean:
	@echo "⚠️  This will remove all containers and data volumes."
	@echo "Press Ctrl+C to cancel, or wait 5 seconds to continue..."
	@sleep 5
	@echo ""
	@echo "Stopping and removing containers..."
	docker compose down -v
	@echo ""
	@echo "✅ Cleanup complete!"
