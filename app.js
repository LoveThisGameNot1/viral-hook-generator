const form = document.getElementById('hook-form');
const topicInput = document.getElementById('topic');
const resultsDiv = document.getElementById('results');
const hookList = document.getElementById('hook-list');
const paywall = document.getElementById('paywall');

let usageCount = parseInt(localStorage.getItem('hookUsageCount')) || 0;

function checkLimit() {
    if (usageCount >= 3) {
        form.classList.add('hidden');
        paywall.classList.remove('hidden');
        return true;
    }
    return false;
}

function generateHooks(topic) {
    const topicCapitalized = topic.charAt(0).toUpperCase() + topic.slice(1);
    
    // Some basic templates for "virality"
    return [
        `Hör auf, Fehler bei ${topicCapitalized} zu machen. Hier sind 5 simple Regeln, die alles verändern: 🧵`,
        `Die meisten Leute scheitern an ${topicCapitalized}, weil sie das EINE Geheimnis ignorieren. Ein Thread darüber, wie du es richtig machst: 👇`,
        `Ich habe Hunderte Stunden damit verbracht, ${topicCapitalized} zu studieren. Hier ist die harte Wahrheit, die dir niemand sagt:`,
        `${topicCapitalized} ist tot. Was du in 2026 stattdessen tun solltest:`,
        `Vergiss alles, was du über ${topicCapitalized} weißt. Dieser 2-Minuten-Hack bringt dir 10x mehr Ergebnisse:`
    ];
}

form.addEventListener('submit', (e) => {
    e.preventDefault();
    if (checkLimit()) return;

    const topic = topicInput.value.trim();
    if (!topic) return;

    const hooks = generateHooks(topic);
    
    // Increment and save usage
    usageCount++;
    localStorage.setItem('hookUsageCount', usageCount);

    // Render hooks
    hookList.innerHTML = '';
    hooks.forEach(hook => {
        const li = document.createElement('li');
        li.className = 'bg-gray-100 p-4 rounded-xl border-l-4 border-blue-500 shadow-sm text-gray-800 text-lg hover:bg-blue-50 transition cursor-pointer';
        li.textContent = hook;
        li.onclick = () => {
            navigator.clipboard.writeText(hook);
            li.textContent = "Kopiert! ✅";
            setTimeout(() => li.textContent = hook, 1500);
        };
        hookList.appendChild(li);
    });

    resultsDiv.classList.remove('hidden');

    // Check limit for next time
    checkLimit();
});

// Initial check
checkLimit();