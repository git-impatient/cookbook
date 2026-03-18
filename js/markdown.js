function escapeHtml(unsafe) {
    return unsafe
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
}

const classMap = {
    h1: 'headline hl3',
    h2: 'headline hl4',
    img: 'media',
}
const bindings = Object.keys(classMap)
    .map(key => ({
        type: 'output',
        regex: new RegExp(`<${key}`, 'g'),
        replace: `<${key} class="${classMap[key]}"`
    }));
const converter = new showdown.Converter({
    extensions: [...bindings],
    noHeaderId: true // important to add this, else regex match doesn't work
});

function include(filename, id) {
    $.get(filename, function(response) {
        var html = converter.makeHtml(response);
        var column = $("#" + id).closest('.column');
        $("#" + id).html(html);
        if (!column.find('.column-body').length) {
            $("#" + id).wrap('<div class="column-body"></div>');
            column.append('<button class="expand-btn" onclick="toggleColumn(this)">Read more \u25bc</button>');
        }
    });
}

function toggleColumn(btn) {
    var body = btn.previousElementSibling;
    body.classList.toggle('expanded');
    btn.textContent = body.classList.contains('expanded') ? 'Read less \u25b2' : 'Read more \u25bc';
}
