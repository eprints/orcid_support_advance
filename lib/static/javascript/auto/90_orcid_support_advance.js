
// Hide putcode field in workflow

function hidePutcode() {
    var ths = document.querySelectorAll('[id*="_creators_th_"], [id*="_editors_th_"]');
    var inputs = document.querySelectorAll('[class*="ep_eprint_creators_putcode"], [class*="ep_eprint_editors_putcode"]');
    var tds = [];

    ths.forEach(function(item) {
        if (/^ORCID Put.*$/gmi.test(item.innerText))
        {
            item.style.display = "none";
        }
    });

    inputs.forEach(function(input) {
        tds.push(input.parentNode);
    });

    tds.forEach(function(td) {
        td.style.display = "none";
    });
}

Ajax.Responders.register({
    onComplete: hidePutcode
});

window.onload = hidePutcode;
