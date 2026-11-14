import router from '@system.router';
export default {
    data: {},
    onShow() {
        this.timer = setTimeout(function () { router.replace({ uri: 'pages/main/main' }); },400);
    },
    onDestroy() { if (this.timer) { clearTimeout(this.timer); } }
};
