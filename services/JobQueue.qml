pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Configurable properties
    property int maxConcurrentJobs: 3
    property int cacheTtlMs: 5000 // Default 5 seconds
    property int maxCacheEntries: 100

    // Internal state
    property var _jobQueue: [] // { job, resolve, reject }
    property var _activeJobs: ({}) // jobId: { job, process, timer, subscribers: [{resolve, reject}], output, status, progress }
    property var _jobCache: ({}) // jobKey: { result, timestamp, success, error }

    // Public reactive properties for diagnostics
    property int queuedJobsCount: _jobQueue.length
    property int activeJobsCount: Object.keys(_activeJobs).length
    property int totalJobsStarted: 0
    property int totalJobsCompleted: 0
    property int totalJobsFailed: 0
    property int totalJobsCancelled: 0
    property var currentJobs: Object.values(_activeJobs).map(j => ({ id: j.job.id, name: j.job.name, status: j.status, progress: j.progress, startTime: j.job.startTime }))
    property var cachedResults: Object.keys(_jobCache).map(key => ({ key: key, timestamp: _jobCache[key].timestamp, success: _jobCache[key].success }))

    /**
     * Submits a job to the queue.
     * @param name A descriptive name for the job (e.g., "cpu-stats").
     * @param commandArray The shell command and arguments as a list of strings.
     * @param options Object with:
     *   - `priority` (int, default 0): Higher number means higher priority.
     *   - `timeoutMs` (int, default 15000): Max execution time.
     *   - `cacheKey` (string, optional): If provided, result will be cached and duplicate jobs coalesced.
     *   - `retryCount` (int, default 0): Number of times to retry on failure.
     *   - `coalesce` (bool, default true): Whether to coalesce duplicate jobs with the same cacheKey.
     * @returns A Promise that resolves with the job output or rejects with an error message.
     */
    function submitJob(name, commandArray, options) {
        options = options || {};
        const priority = options.priority ?? 0;
        const timeoutMs = options.timeoutMs ?? 15000;
        const cacheKey = options.cacheKey;
        const retryCount = options.retryCount ?? 0;
        const coalesce = options.coalesce ?? true;

        const jobId = `job_${Date.now()}_${Math.floor(Math.random() * 1000)}`;

        // 1. Check cache first if cacheKey provided
        if (cacheKey && _jobCache[cacheKey] && (Date.now() - _jobCache[cacheKey].timestamp < root.cacheTtlMs)) {
            const cached = _jobCache[cacheKey];
            if (cached.success) {
                return Promise.resolve(cached.result);
            } else {
                return Promise.reject(cached.error);
            }
        }

        // 2. Coalesce duplicate jobs if requested
        if (coalesce && cacheKey) {
            for (const activeJobId in _activeJobs) {
                const active = _activeJobs[activeJobId];
                if (active.job.cacheKey === cacheKey && (active.status === "queued" || active.status === "running")) {
                    console.debug(`[JobQueue] Coalescing job ${name} (${jobId}) with active job ${active.job.name} (${active.job.id})`);
                    return new Promise((resolve, reject) => {
                        active.subscribers.push({ resolve, reject });
                    });
                }
            }
        }

        const job = {
            id: jobId,
            name: name,
            command: commandArray,
            priority: priority,
            timeoutMs: timeoutMs,
            cacheKey: cacheKey,
            retryCount: retryCount,
            currentRetry: 0,
            startTime: 0,
            status: "queued"
        };

        // Using Qt.callLater to ensure the Promise is returned before adding to queue
        return new Promise((resolve, reject) => {
            _jobQueue.push({ job, resolve, reject });
            _jobQueue.sort((a, b) => b.job.priority - a.job.priority); // Sort by priority
            _processQueue();
        });
    }

    /**
     * Cancels a job.
     * If the job is queued, it's removed. If running, it's terminated.
     * If multiple subscribers, only current subscriber is cancelled unless all are.
     * @param jobId The ID of the job to cancel.
     * @returns true if the job was found and cancelled, false otherwise.
     */
    function cancelJob(jobId) {
        // Remove from queue
        const queueIdx = _jobQueue.findIndex(item => item.job.id === jobId);
        if (queueIdx !== -1) {
            const { job, reject } = _jobQueue.splice(queueIdx, 1)[0];
            reject(`Job ${job.name} (${job.id}) cancelled`);
            totalJobsCancelled++;
            queuedJobsCount = _jobQueue.length;
            return true;
        }

        // Cancel running job
        if (_activeJobs[jobId]) {
            const record = _activeJobs[jobId];
            record.subscribers = record.subscribers.filter(sub => {
                sub.reject(`Job ${record.job.name} (${record.job.id}) cancelled`);
                return false; // Remove all subscribers for now; proper ref counting is complex
            });

            if (record.subscribers.length === 0) {
                record.timer.stop();
                if (record.process) record.process.running = false;
                _finishJob(jobId, false, `Job ${record.job.name} (${record.job.id}) cancelled`); // This will clean up
            } else {
                // Job still has active subscribers, do not terminate actual work
                console.debug(`[JobQueue] Not terminating job ${record.job.name} (${record.job.id}): still has active subscribers.`);
            }
            return true;
        }
        return false;
    }

    function _processQueue() {
        if (activeJobsCount >= maxConcurrentJobs || _jobQueue.length === 0) {
            return;
        }

        const { job, resolve, reject } = _jobQueue.shift();
        job.startTime = Date.now();
        job.status = "running";

        totalJobsStarted++;
        activeJobsCount = Object.keys(_activeJobs).length + 1; // Update count

        const collector = stdioCollectorComp.createObject(root);
        collector.streamFinished.connect(function () {
            const record = _activeJobs[job.id];
            if (record) record.output = collector.text ?? "";
        });

        const timer = timerComp.createObject(root, {
            interval: job.timeoutMs,
            repeat: false
        });

        const realProc = processComp.createObject(root);
        realProc.command = job.command;
        realProc.stdout = collector;

        const record = {
            job: job,
            process: realProc,
            timer: timer,
            subscribers: [{ resolve, reject }], // Store initial subscriber
            output: "",
            status: "running",
            progress: 0
        };

        _activeJobs[job.id] = record;

        timer.triggered.connect(function () {
            console.warn(`[JobQueue] Job timed out: ${job.name} (${job.id})`);
            realProc.running = false;
            _finishJob(job.id, false, `Job ${job.name} (${job.id}) timed out`);
        });

        realProc.exited.connect(function (exitCode) {
            const success = exitCode === 0;
            const errorMsg = success ? "" : `Process exited with code ${exitCode}`;
            _finishJob(job.id, success, errorMsg, record.output || collector.text || "");
        });

        timer.start();
        realProc.running = true;

        queuedJobsCount = _jobQueue.length; // Update count
    }

    function _finishJob(jobId, success, errorMsg, output) {
        const record = _activeJobs[jobId];
        if (!record) return;

        record.timer.stop();
        record.timer.destroy();
        if (record.process.stdout) record.process.stdout.destroy();
        record.process.destroy();

        const duration = Date.now() - record.job.startTime;

        if (success) {
            totalJobsCompleted++;
            record.job.status = "completed";
            // Resolve all subscribers
            record.subscribers.forEach(sub => sub.resolve(output));
            // Cache result if cacheKey provided
            if (record.job.cacheKey) {
                _jobCache[record.job.cacheKey] = { result: output, timestamp: Date.now(), success: true, error: null };
                _cleanupCache();
            }
        } else {
            totalJobsFailed++;
            record.job.status = "failed";
            if (record.job.currentRetry < record.job.retryCount) {
                console.warn(`[JobQueue] Job ${record.job.name} (${record.job.id}) failed, retrying (${record.job.currentRetry + 1}/${record.job.retryCount})...`);
                record.job.currentRetry++;
                record.job.status = "queued";
                _jobQueue.unshift({ job: record.job, resolve: record.subscribers[0].resolve, reject: record.subscribers[0].reject }); // Re-add to front of queue
                _jobQueue.sort((a, b) => b.job.priority - a.job.priority); // Re-sort for priority
                queuedJobsCount = _jobQueue.length;
            } else {
                // Reject all subscribers
                record.subscribers.forEach(sub => sub.reject(errorMsg));
                // Cache failure if cacheKey provided
                if (record.job.cacheKey) {
                    _jobCache[record.job.cacheKey] = { result: null, timestamp: Date.now(), success: false, error: errorMsg };
                    _cleanupCache();
                }
            }
        }

        delete _activeJobs[jobId];
        activeJobsCount = Object.keys(_activeJobs).length;

        _processQueue();
    }

    function _cleanupCache() {
        const now = Date.now();
        for (const key in _jobCache) {
            if (now - _jobCache[key].timestamp > root.cacheTtlMs) {
                delete _jobCache[key];
            }
        }
        // Enforce max cache entries
        const keys = Object.keys(_jobCache);
        if (keys.length > root.maxCacheEntries) {
            // Simple eviction: remove oldest
            keys.sort((a, b) => _jobCache[a].timestamp - _jobCache[b].timestamp);
            for (let i = 0; i < keys.length - root.maxCacheEntries; i++) {
                delete _jobCache[keys[i]];
            }
        }
    }

    Component {
        id: processComp
        Process {}
    }

    Component {
        id: stdioCollectorComp
        StdioCollector {}
    }

    Component {
        id: timerComp
        Timer {}
    }
}
