pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property int maxConcurrentJobs: 3
    property int activeJobsCount: 0
    property var jobQueue: []
    property var activeJobs: ({})
    property var completedHistory: []

    // Metrics & Diagnostics
    property int totalJobsStarted: 0
    property int totalJobsSucceeded: 0
    property int totalJobsFailed: 0
    property int totalJobsCancelled: 0

    function runTask(name, commandArray, onCompleteCallback, onErrorCallback, timeoutMs) {
        timeoutMs = timeoutMs || 15000;
        const jobId = "job_" + Date.now() + "_" + Math.floor(Math.random() * 1000);

        const job = {
            id: jobId,
            name: name,
            command: commandArray,
            onComplete: onCompleteCallback,
            onError: onErrorCallback,
            timeout: timeoutMs,
            startTime: 0,
            status: "queued"
        };

        jobQueue.push(job);
        _processQueue();
        return jobId;
    }

    function cancelTask(jobId) {
        // Remove from queue if not started
        const queueIdx = jobQueue.findIndex(j => j.id === jobId);
        if (queueIdx !== -1) {
            jobQueue.splice(queueIdx, 1);
            totalJobsCancelled++;
            return true;
        }

        // Cancel running task
        if (activeJobs[jobId]) {
            const record = activeJobs[jobId];
            if (record.timer) record.timer.stop();
            if (record.process) record.process.running = false;
            delete activeJobs[jobId];
            activeJobsCount--;
            totalJobsCancelled++;
            _processQueue();
            return true;
        }

        return false;
    }

    function _processQueue() {
        if (activeJobsCount >= maxConcurrentJobs || jobQueue.length === 0) {
            return;
        }

        const job = jobQueue.shift();
        job.startTime = Date.now();
        job.status = "running";

        activeJobsCount++;
        totalJobsStarted++;

        const collector = collectorComp.createObject(root);
        collector.streamFinished.connect(function () {
            const r = activeJobs[job.id];
            if (r) r.output = collector.text ?? "";
        });

        const timer = timerComp.createObject(root, {
            interval: job.timeout,
            repeat: false
        });

        const realProc = workerProcComp.createObject(root);
        realProc.command = job.command;
        realProc.stdout = collector;

        const record = {
            job: job,
            process: realProc,
            timer: timer,
            output: ""
        };

        activeJobs[job.id] = record;

        timer.triggered.connect(function () {
            console.warn(`[WorkerSupervisor] Job timed out: ${job.name} (${job.id})`);
            realProc.running = false;
            _finishJob(job.id, false, "Timeout exceeded");
        });

        realProc.exited.connect(function (exitCode) {
            const success = exitCode === 0;
            const errorMsg = success ? "" : `Process exited with code ${exitCode}`;
            _finishJob(job.id, success, errorMsg, record.output || collector.text || "");
        });

        timer.start();
        realProc.running = true;
    }

    function _finishJob(jobId, success, errorMsg, output) {
        const record = activeJobs[jobId];
        if (!record) return;

        if (record.timer) {
            record.timer.stop();
            record.timer.destroy();
        }

        const duration = Date.now() - record.job.startTime;

        if (success) {
            totalJobsSucceeded++;
            if (record.job.onComplete) record.job.onComplete(output);
        } else {
            totalJobsFailed++;
            if (record.job.onError) record.job.onError(errorMsg);
        }

        completedHistory.unshift({
            id: jobId,
            name: record.job.name,
            durationMs: duration,
            success: success,
            error: errorMsg
        });

        if (completedHistory.length > 50) completedHistory.pop();

        if (record.process) {
            record.process.destroy();
        }

        delete activeJobs[jobId];
        activeJobsCount--;

        _processQueue();
    }

    Component {
        id: workerProcComp
        Process {
        }
    }

    Component {
        id: collectorComp
        StdioCollector {
        }
    }

    Component {
        id: timerComp
        Timer {
        }
    }
}
