pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

Item {
    id: root
    implicitHeight: layout.implicitHeight + 20
    implicitWidth: layout.implicitWidth + 20

    ColumnLayout {
        id: layout
        anchors.margins: 10
        anchors.fill: parent
        spacing: 5

        Text {
            text: `JobQueue Diagnostics`
            font.bold: true
            color: "#fff"
        }

        Text {
            text: `Queued: ${JobQueue.queuedJobsCount} | Active: ${JobQueue.activeJobsCount} | Completed: ${JobQueue.totalJobsCompleted} | Failed: ${JobQueue.totalJobsFailed}`
            color: "#aaa"
            font.pixelSize: 12
        }

        Text {
            text: `Max Concurrent: ${JobQueue.maxConcurrentJobs} | Cache TTL: ${JobQueue.cacheTtlMs}ms`
            color: "#888"
            font.pixelSize: 11
        }

        Text {
            text: `Cached Results: ${JobQueue.cachedResults.length}`
            color: "#666"
            font.pixelSize: 11
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#444"
        }

        Repeater {
            model: JobQueue.currentJobs
            delegate: Text {
                text: `${modelData.name}: ${modelData.status} (${Math.round((Date.now() - modelData.startTime) / 1000)}s)`
                color: modelData.status === "running" ? "#0f0" : modelData.status === "queued" ? "#ff0" : "#f0f"
                font.pixelSize: 10
            }
        }
    }
}
