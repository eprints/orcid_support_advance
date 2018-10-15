
// Hide putcode field in workflow

function hidePutcode() {
    var ths = document.querySelectorAll('[id*="_creators_th_"]');
    var inputs = document.querySelectorAll('[class*="ep_eprint_creators_putcode"]');
    var tds = [];

    ths.forEach(function(item) {
        if (/^ORCID Put.*$/gmi.test(item.innerHTML))
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

window.onload = hidePutcode;
