// Fit the Kancolle game frame to the viewport on iOS.
// Ported from the iOS 18 Safari bookmarklet (kancollefit_20251017), without pinch zoom.
(($, _) => {
    if (_.kancolleFit) return;

    const hideSelectors = ['.dmm-ntgnavi', '.area-naviapp', '#ntg-recommend', '#wrapper-dmm-ntg', '#footer', '#dmm-ntg-login-user', '.main-ntg'];
    const viewportContent = 'width=device-width,initial-scale=1.0,maximum-scale=10.0,user-scalable=yes,viewport-fit=cover';

    let gf = null,
        saved = null,
        observer = null,
        resizeTimer = 0,
        throttleTimer = 0,
        lastApplyTime = 0,
        lastOrientation = 0;

    const findTarget = () => $.getElementById('game_frame') || $.getElementById('htmlWrap') || $.getElementById('flashWrap');

    const hide = (e) => {
        if (e.style.display === 'none') return;
        saved.hidden.push([e, e.style.display]);
        e.style.display = 'none';
    };

    const hideUI = () => {
        hideSelectors.forEach(s => {
            const e = $.querySelector(s);
            if (e && !e.contains(gf)) hide(e);
        });
        $.querySelectorAll('nav,header,footer').forEach(e => {
            if (!e.contains(gf)) hide(e);
        });
        const greset = $.querySelector('.gamesResetStyle');
        if (greset) {
            if (!saved.greset) saved.greset = [greset, greset.style.cssText];
            greset.style.background = 'transparent';
            greset.style.padding = '0';
            greset.style.margin = '0';
            greset.style.border = 'none';
            greset.style.boxShadow = 'none';
        }
    };

    const applyScale = (force) => {
        if (!saved) return;
        const now = Date.now();
        if (!force && now - lastApplyTime < 200) {
            // Run once more after the throttle window so the last change is not lost
            clearTimeout(throttleTimer);
            throttleTimer = setTimeout(() => applyScale(false), 200 - (now - lastApplyTime));
            return;
        }
        lastApplyTime = now;
        hideUI();
        const html = $.documentElement,
            gs = gf.style,
            gw = gf.offsetWidth,
            gh = gw * 0.6,
            w = html.clientWidth,
            h = _.innerHeight;
        if (!gw) return;
        const scale = w / h < 1 / .6 ? w / gw : h / gh;
        gs.transform = 'scale(' + scale + ')';
        gs.left = w < gw ? '-' + (gw - w) / 2 + 'px' : '0';
        gs.top = '0';
        _.scrollTo(0, 0);
    };

    const onResize = () => {
        clearTimeout(resizeTimer);
        resizeTimer = setTimeout(() => applyScale(false), 100);
    };

    const onOrientationChange = () => {
        const angle = screen.orientation?.angle || 0;
        if (angle !== lastOrientation) {
            lastOrientation = angle;
            setTimeout(() => applyScale(false), 200);
        }
    };

    _.kancolleFit = () => {
        if (saved && !$.contains(gf)) _.kancolleUnfit();
        if (!saved) {
            gf = findTarget();
            if (!gf) return false;
            const html = $.documentElement;
            let vp = $.querySelector('meta[name=viewport]');
            saved = {
                vp: vp,
                vpContent: vp ? vp.content : null,
                html: html.style.cssText,
                body: $.body.style.cssText,
                gf: gf.style.cssText,
                hidden: [],
                greset: null,
            };
            if (!vp) {
                vp = $.createElement('meta');
                vp.name = 'viewport';
                $.querySelector('head').appendChild(vp);
                saved.vp = vp;
            }
            vp.content = viewportContent;
            html.style.overflow = 'hidden';
            html.style.background = '#000';
            $.body.style.cssText = 'min-width:0;overflow:hidden;margin:0;background:#000';
            const gs = gf.style;
            gs.position = 'absolute';
            gs.margin = '0 auto';
            gs.right = '0';
            gs.top = '0';
            gs.zIndex = '100';
            gs.transformOrigin = '50% 0px';
            lastOrientation = screen.orientation?.angle || 0;
            _.addEventListener('resize', onResize);
            _.addEventListener('orientationchange', onOrientationChange);
            observer = new MutationObserver(() => {
                setTimeout(() => applyScale(false), 100);
            });
            observer.observe($.body, {childList: true, subtree: true});
        }
        applyScale(true);
        return true;
    };

    _.kancolleUnfit = () => {
        if (!saved) return;
        _.removeEventListener('resize', onResize);
        _.removeEventListener('orientationchange', onOrientationChange);
        clearTimeout(resizeTimer);
        clearTimeout(throttleTimer);
        if (observer) observer.disconnect();
        observer = null;
        if (saved.vpContent === null) {
            saved.vp.remove();
        } else {
            saved.vp.content = saved.vpContent;
        }
        $.documentElement.style.cssText = saved.html;
        $.body.style.cssText = saved.body;
        gf.style.cssText = saved.gf;
        saved.hidden.forEach(([e, display]) => {
            e.style.display = display;
        });
        if (saved.greset) saved.greset[0].style.cssText = saved.greset[1];
        saved = null;
        gf = null;
    };
})(document, window)
