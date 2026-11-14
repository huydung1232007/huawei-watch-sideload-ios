// Small ES5-compatible validator for API 6/JerryScript. The first milestone
// accepts explicitly labelled sample packets only, never live route guidance.
function reply(message,expected) {
    if (!message || message.t !== 'navmini.status' || message.v !== 1 ||
        message.demo !== true || !expected || message.n !== expected) { return null; }
    var limits = { instruction: 40, distance: 16, turn: 12, remaining: 16,
        duration: 16, eta: 12, speed: 16, phoneTime: 12 };
    var keys = Object.keys(limits);
    for (var i = 0; i < keys.length; i++) {
        var key = keys[i];
        if (typeof message[key] !== 'string' || message[key].length > limits[key]) { return null; }
    }
    if (message.turn !== 'left' && message.turn !== 'right' && message.turn !== 'straight') { return null; }
    return { instruction: message.instruction, distance: message.distance,
        arrow: message.turn === 'left' ? '<' : (message.turn === 'right' ? '>' : '^'),
        summary: message.remaining + ' - ' + message.duration,
        footer: message.eta + ' - ' + message.speed,
        status: 'Da nhan ' + message.phoneTime };
}
export default { reply: reply };
