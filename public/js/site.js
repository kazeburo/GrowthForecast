function setHxrpost() {
  var myform = this, $myform = $(myform);
  var alert = $('<div class="alert alert-danger">System Error!</div>');
  alert.hide();
  $myform.first().prepend(alert);
  $myform.submit(function(e){
    $myform.find('.alert').hide();
    $myform.find('.validator-message').detach();
    $myform.find('.clearfix').removeClass('error');
    $.ajax({
      type: 'POST',
      url: myform.action,
      data: $myform.serialize(),
      success: function(data) {
        $myform.find('.alert').hide();
        if ( data.error == 0 ) {
            location.href = data.location;
        }
        else {
            $.each(data.messages, function (param,message) {
              var helpblock = $('<p class="validator-message help-block"></p>');
              helpblock.text(message);
              $myform.find('[name="'+param+'"]').parents('div[class^="col-sm-"]').first().append(helpblock);
              $myform.find('[name="'+param+'"]').parents('div[class^="col-sm-"]').first().addClass('has-error');
              if ( param.match(/-2$/) ) {
                $myform.find('[name="path-add"]').parents('div[class^="col-sm-"]').first().append(helpblock);
                $myform.find('[name="path-add"]').parents('div[class^="col-sm-"]').first().addClass('has-error');
              }
            });
        }
      },
      error: function() {
        $myform.find('.alert').show();
      }
    });
    e.preventDefault();
  });
};

function setHxrConfirmBtn() {
  var mybtn = this;
  var modal = $('<div class="modal fade"><div class="modal-dialog"><div class="modal-content">'+
'<form method="post" action="#">'+
'<div class="modal-header"><h3>confirm</h3></div>'+
'<div class="modal-body"><div class="alert alert-error hide">System Error!</div><p>confirm</p></div>'+
'<div class="modal-footer"><input type="submit" class="btn btn-danger" value="confirm" /></div>'+
'</form></div></div></div>');
  modal.find('h3').text($(mybtn).text());
  modal.find('input[type=submit]').attr('value',$(mybtn).text());
  modal.find('.modal-body > p').text( $(mybtn).data('confirm') );
  modal.find('form').submit(function(e){
    $.ajax({
      type: 'POST',
      url: $(mybtn).data('uri'),
      data: modal.find('form').serialize(),
      success: function(data) {
        modal.find('.alert').hide();
        if ( data.error == 0 ) {
          location.href = data.location;
        }
      },
      error: function() {
        modal.find('.alert').show();
      }
    });
    e.preventDefault();
    return false;
  });
  $(mybtn).click(function(e){
    modal.modal({
      show: true,
      backdrop: true,
      keyboard: true,
    });
    e.preventDefault();
    return false;
  });
};


function add_new_row(e) {
  var path = $('#path-add').val();
  var type = $('#type-add').val();
  var gmode = $('#gmode-add').val();
  var stack = $('#stack-add').val();

  var tr = $('<tr></tr>');
  tr.append('<td>'+$('#type-add option:selected').html()+'<input type="hidden" name="type-2" value="'+type+'" /><input type="hidden" name="path-2" value="'+path+'" /></td>');
  tr.append('<td>dummy</td>');
  tr.children('td:last-child').text('/'+$('select[name="path-add-service"] option:selected').html()+'/'+$('select[name="path-add-section"] option:selected').html()+'/'+$('#path-add option:selected').html());
  tr.append('<td style="text-align:center">'+$('#gmode-add option:selected').html()+'<input type="hidden" name="gmode-2" value="'+gmode+'" /></td>');
  tr.append('<td style="text-align:center">'+$('#stack-add option:selected').html()+'<input type="hidden" name="stack-2" value="'+stack+'" /></td>');
  tr.append('<td style="text-align:center"><span class="table-order-pointer table-order-up">⬆</span><span class="table-order-pointer table-order-down">⬇</span> | <span class="table-order-remove">✖</span></td>')
  tr.appendTo($('table#add-data-tbl'));

  $('#add-data-tbl').find('tr:last').addClass('can-table-order');
  $('#add-data-tbl').find('span.table-order-up:last').click(table_order_up);
  $('#add-data-tbl').find('span.table-order-down:last').click(table_order_down);
  $('#add-data-tbl').find('span.table-order-remove:last').click(table_order_remove);

  var myform = $('#path-add').parents('form').first();
  setTimeout(function(){preview_complex_graph(myform)},10);
  e.preventDefault();
  return false;
}

function table_order_up(e) {
  var btn = this;
  var mytr = $(this).parents('tr.can-table-order').first();
  if ( mytr ) {
    var prevtr = mytr.prev('tr.can-table-order');
    mytr.insertBefore(prevtr);
  }
  var myform = $(this).parents('form').first();
  setTimeout(function(){preview_complex_graph(myform)},10);
  e.preventDefault();
  return false;
};

function table_order_down(e) {
  var btn = this;
  var mytr = $(this).parents('tr.can-table-order').first();
  if ( mytr ) {
    var nexttr = mytr.next('tr.can-table-order');
    mytr.insertAfter(nexttr);
  }
  var myform = $(this).parents('form').first();
  setTimeout(function(){preview_complex_graph(myform)},0);
  e.preventDefault();
  return false;
};

function table_order_remove() {
  var btn = this;
  var mytr = $(this).parents('tr.can-table-order').first();
  var myform = $(this).parents('form').first();
  setTimeout(function(){preview_complex_graph(myform)},10);
  mytr.detach();
};

function preview_complex_graph(myform) {
  var uri =  myform.find('select[name="type-1"]').val() + ':' + myform.find('select[name="path-1"]').val() + ':' + myform.find('select[name="gmode-1"]').val() + ':0';
  var num = myform.find('input[name=type-2]').length;

  for (var i=0; i < num; i++ ) {
      uri += ':'
           + myform.find('input[name="type-2"]').eq(i).val() + ':'
           + myform.find('input[name="path-2"]').eq(i).val() + ':'
           + myform.find('input[name="gmode-2"]').eq(i).val() + ':'
           + myform.find('input[name="stack-2"]').eq(i).val();
  }
  var base = $('ul.nav:first > li:first > a').attr('href');
  var img = $('<img />');
  img.attr('src',base + 'graph/' + uri + '?sumup=' + myform.find('select[name="sumup"]').val());
  $('#preview-graph').children('img').detach();
  img.appendTo($('#preview-graph'));
};

function setTablePreview() {
  $('.table-order-up').click(table_order_up);
  $('.table-order-down').click(table_order_down);
  $('.table-order-remove').click(table_order_remove);
  $('#complex-form select[name="sumup"]').change(function(){
    setTimeout(function(){ preview_complex_graph($('#complex-form')) },10);
  });
  $('#complex-form select[name$="-1"]').change(function(){
    setTimeout(function(){ preview_complex_graph($('#complex-form')) },10);
  });

  var service_tree;
  $.ajax({
    url: $('#service_tree').data('endpoint'),
    cache: false,
    async: false,
    dataType: 'json'
  }).done(function(data){ service_tree = data })
    .fail(function(){
        var alert = $('<div class="alert alert-danger">System Error! Please reload this page</div>');
        $('#service_tree').append(alert);
    });

  $('#complex-form select[name="path-1-service"]').change(function(){
    var service_select = $(this);
    setTimeout(function(){
      var path_1_section = $('#complex-form select[name="path-1-section"]');
      path_1_section.children().detach();
      var section = $.grep(service_tree,function(n,i){ return (n["name"]==service_select.val())});
      $.map(section[0]["sections"], function(s,i){
        var opttag = $('<option value="dummy">dummy</option>');
        opttag.text(s["name"]);
        opttag.attr('value',s["name"]);
        path_1_section.append(opttag.clone());
      })
      var path_1_g = $('#complex-form select[name="path-1"]');
      path_1_g.children().detach();
      $.map(section[0]["sections"][0]["graphs"], function(g,i){
        var opttag = $('<option value="dummy">dummy</option>');
        opttag.text(g["graph_name"]);
        opttag.attr('value',g["id"]);
        path_1_g.append(opttag.clone());
      })
      preview_complex_graph($('#complex-form')) },10);
  });

  $('#complex-form select[name="path-1-section"]').change(function(){
    var section_select = $(this);
    setTimeout(function(){
      var path_1_g = $('#complex-form select[name="path-1"]');
      path_1_g.children().detach();
      var section = $.grep(service_tree,function(n,i){
        return ( n["name"] == $('#complex-form select[name="path-1-service"]').val())
      });
      var path_1_g = $('#complex-form select[name="path-1"]');
      path_1_g.children().detach();
      $.map(section[0]["sections"], function(s,i) {
        if ( s["name"] == section_select.val() ) {
          $.map(s["graphs"], function(g,i){
            var opttag = $('<option value="dummy">dummy</option>');
            opttag.text(g["graph_name"]);
            opttag.attr('value',g["id"]);
            path_1_g.append(opttag.clone());
         });
       }
     });
     preview_complex_graph($('#complex-form')) },10);
  });

  $('#complex-form select[name="path-add-service"]').change(function(){
    var service_select = $(this);
    setTimeout(function(){
      var path_section = $('#complex-form select[name="path-add-section"]');
      path_section.children().detach();
      var section = $.grep(service_tree,function(n,i){ return (n["name"]==service_select.val())});
      $.map(section[0]["sections"], function(s,i){
        var opttag = $('<option value="dummy">dummy</option>');
        opttag.text(s["name"]);
        opttag.attr('value',s["name"]);
        path_section.append(opttag.clone());
      });
      var path_g = $('#complex-form select[name="path-add"]');
      path_g.children().detach();
      $.map(section[0]["sections"][0]["graphs"], function(g,i){
        var opttag = $('<option value="dummy">dummy</option>');
        opttag.text(g["graph_name"]);
        opttag.attr('value',g["id"]);
        path_g.append(opttag.clone());
      });
    });
  });

  $('#complex-form select[name="path-add-section"]').change(function(){
    var section_select = $(this);
    setTimeout(function(){
      var path_g = $('#complex-form select[name="path-add"]');
      path_g.children().detach();
      var section = $.grep(service_tree,function(n,i){
        return ( n["name"] == $('#complex-form select[name="path-add-service"]').val())
      });
      var path_g = $('#complex-form select[name="path-add"]');
      path_g.children().detach();
      $.map(section[0]["sections"], function(s,i) {
        if ( s["name"] == section_select.val() ) {
          $.map(s["graphs"], function(g,i){
            var opttag = $('<option value="dummy">dummy</option>');
            opttag.text(g["graph_name"]);
            opttag.attr('value',g["id"]);
            path_g.append(opttag.clone());
          });
        }
      });
    });
  });
  preview_complex_graph($('#complex-form'));
}

function setColorPallets() {
  var input = $(this);
  var preview = $('<div class="input-group-static" style="border-top-left-radius: 4px;border-bottom-left-radius: 4px;border: 1px solid #ccc;border-right: 0">&nbsp;&nbsp;&nbsp;&nbsp;</div>');
  input.before(preview);
  preview.css('background-color',input.val());
  input.change(function(){
      preview.css('background-color',input.val());
  });
  var colors = ["#cccccc","#cccc77","#cccc11","#cc77cc","#cc7777","#cc7711","#cc11cc","#cc1177","#cc1111","#77cccc","#77cc77","#77cc11","#7777cc","#777777","#777711","#7711cc","#771177","#771111","#11cccc","#11cc77","#11cc11","#1177cc","#117777","#117711","#1111cc","#111177","#111111"];
  var pallet = $('<div style="display:none;border:solid 1px #000;width:158px;padding:1px;background-color:#222;position:absolute"></div>');
  pallet.append('<div style="margin:1px;display:inline-block;width:20px;height:20px;cursor:pointer;color:#eee;text-align:center;">✖</div>');
  pallet.children().first().click(function(){
    pallet.toggle();
  });
  $.map(colors, function (code,idx) {
      var piece = $('<div style="margin:1px;display:inline-block;'
                    + 'width:20px;height:20px;cursor:pointer">&nbsp;</div>');
      piece.css('background-color',code);
      piece.click(function(){
         input.val(code);
         input.change();
         pallet.toggle();
      });
      pallet.append(piece);
  });
  input.after(pallet);
  input.click(function(){
    var pos = $(this).position();
    var width = $(this).outerWidth(true);
    pallet.css('top',pos.top);
    pallet.css('z-index',999);
    pallet.css('left',pos.left+width);
    pallet.toggle();
  });
}

function fold_all(e) {
  $('.service_sections, .section_graphs').filter('.in').collapse('hide');
  e.preventDefault();
  return false;
}

function expand_all(e) {
  $('.service_sections, .section_graphs').not('.in').collapse('show');
  e.preventDefault();
  return false;
}
