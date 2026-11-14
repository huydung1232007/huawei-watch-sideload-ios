import bridge from '../../common/bridge.js';
import protocol from '../../common/protocol.js';

export default {
    data: { status: 'Cho iPhone', arrow: '-', distance: '-- m', instruction: 'DU LIEU THU',
        summary: '-- km - -- phut', footer: '--:-- - -- km/h', button: 'Thu ket noi' },
    onInit() {
        var that = this;
        this.alive = true;
        this.pending = 0;
        bridge.listen(function (message) {
            if (!that.alive) { return; }
            var next = protocol.reply(message,that.pending);
            if (!next) { return; }
            var nonce = that.pending;
            that.pending = 0;
            if (that.timer) { clearTimeout(that.timer); that.timer = null; }
            that.status = next.status; that.arrow = next.arrow; that.distance = next.distance;
            that.instruction = next.instruction; that.summary = next.summary; that.footer = next.footer;
            that.button = 'Thu lai';
            bridge.send({ t: 'navmini.rendered', v: 1, n: nonce });
        });
        bridge.start(function (problem) {
            if (that.alive && problem) { that.status = 'Link: ' + problem; }
        });
    },
    onDestroy() {
        this.alive = false; this.pending = 0;
        if (this.timer) { clearTimeout(this.timer); this.timer = null; }
        bridge.listen(null);
    },
    request() {
        if (this.pending) { return; }
        var that = this;
        var nonce = (Date.now() % 900000000) + 1;
        this.pending = nonce; this.status = 'Dang gui...'; this.button = 'Dang cho...';
        this.timer = setTimeout(function () {
            if (!that.alive || that.pending !== nonce) { return; }
            that.pending = 0; that.status = 'Chua nhan - mo app iPhone'; that.button = 'Thu lai';
        },8000);
        bridge.send({ t: 'navmini.hello', v: 1, n: nonce },function (ok) {
            if (that.alive && that.pending === nonce && !ok) { that.status = 'Chua gui duoc - cho iPhone'; }
        });
    }
};
