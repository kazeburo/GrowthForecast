// Copyright 2007-2009 futomi  http://www.html5.jp/
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// cpick.js v1.0.0

(function () {

/* -------------------------------------------------------------------
* constructor
* ----------------------------------------------------------------- */
cpick = function (trigger, target, p) {
	if( typeof(trigger) == "undefined" || ! trigger ) { return; }
	if( typeof(target) == "undefined" || ! target ) { return; }
	if( typeof(p) == "undefined" || ! p ) { return; }
	//
	if( ! /^input$/i.test(target.nodeName) || ! /^text$/.test(target.type) ) { return; }
	if( ! /^(input|button)$/i.test(trigger.nodeName) ) { return; }
	/* -------------------------------------------------------------------
	* default settings
	* ----------------------------------------------------------------- */
	var dp = {
		width: 200,
		height: 160,
		grid: 1,
		gridie: 2,
		show: 3,
		hide: 3,
		coloring: false
	};
	/* -------------------------------
	* initialize parameters
	* ----------------------------- */
	if( typeof(p) == "undefined" ) { p = {}; }
	for( var k in dp ) {
		if( typeof(p[k]) == "undefined" ) {
			p[k] = dp[k];
		}
	}
	// width of progress bar
	p.width = parseFloat(p.width);
	if( p.width < 100 ) {
		p.width = 100;
	} else if( p.width > 400 ) {
		p.width = 400;
	}
	// height of progress bar
	p.height = parseFloat(p.height);
	if( p.height < 100 ) {
		p.height = 100;
	} else if( p.height > 400 ) {
		p.height = 400;
	}
	// grid size of color palette
	p.grid = parseInt(p.grid);
	if( p.grid < 1 ) {
		p.grid = 1;
	} else if( p.grid > 5 ) {
		p.grid = 5;
	}
	// grid size of color palette for Internet Explorer
	p.gridie = parseInt(p.gridie);
	if( p.gridie < 1 ) {
		p.gridie = 1;
	} else if( p.gridie > 5 ) {
		p.gridie = 5;
	}
	// show speed
	p.show = parseInt(p.show);
	if( p.show < 0 ) {
		p.show = 0;
	} else if( p.show > 5 ) {
		p.show = 5;
	}
	// hide speed
	p.hide = parseInt(p.hide);
	if( p.hide < 0 ) {
		p.hide = 0;
	} else if( p.hide > 5 ) {
		p.hide = 5;
	}
	// boolean parameters
	var boolean_params = ["coloring"];
	for( var i=0; i<boolean_params.length; i++ ) {
		var k = boolean_params[i];
		if( typeof(p[k]) == "string" ) {
			if(p[k] == "true") {
				p[k] = true;
			} else if(p[k] == "false") {
				p[k] = false;
			}
		} else if( typeof(p[k]) != "boolean" ) {
			p[k] = dp[k];
		}
	}
	/* -------------------------------
	* save initialize parameters
	* ----------------------------- */
	var initp = {};
	for( var k in p ) {
		var v = p[k];
		initp[k] = v;
	}
	//
	this.p = p;
	this.initp = initp;
	this.nodes = {
		trigger: trigger,
		target: target,
		panel: null,
		palette: null,
		bar: null,
		pind: null,
		bind: null
	};
	// current color
	this.hls = { h:180, l:0.5, s:0.5 };
	this.rgb = { r:63, g:191, b:191 };
};

/* -------------------------------------------------------------------
* prototypes
* ----------------------------------------------------------------- */
var proto = cpick.prototype;

/* -------------------------------------------------------------------
* public methods
* ----------------------------------------------------------------- */

proto.prepare = function() {
	// set the current color
	var text = this.nodes.target.value;
	if( typeof(text) == "string" && text != "" ) {
		var rgb = this._conv_color_to_rgb(text);
		if( rgb != null ) {
			this.rgb = rgb;
			this.hls = this._rgb_to_hls(rgb);
		}
		// coloring the trigger element
		if(this.p.coloring == true) {
			this._coloring_trigger();
		}
	}
};

proto.flip = function() {
	var panel = this.nodes.panel;
	if(panel && this.nodes.panel.style.display != "none") {
		this.hide();
	} else {
		this.show();
	}
};

proto.show = function() {
	var panel = this.nodes.panel;
	if( typeof(panel) == "undefined" || ! panel ) {
		panel = this._create_panel();
		this.nodes.panel = panel;
		panel.style.display = "none";
	} else {
		if(panel._resizing == true) { return; }
	}
	var pos = this._get_element_abs_pos(this.nodes.trigger);
	panel.style.top = pos.top + "px";
	panel.style.left = (pos.left + pos.width + 10) + "px";
	this._show_selected_color_infomations();
	this._set_indicators();
	if(panel.style.display == "none") {
		panel.style.zIndex += 1;
		this._show_element(panel, this.p.show);
	}
};

proto.hide = function() {
	var panel = this.nodes.panel;
	if( panel == null ) { return; }
	if(panel._resizing == true) { return; }
	panel.style.zIndex = 1;
	this._hide_element(panel, this.p.hide);
};

/* -------------------------------------------------------------------
* private methods
* ----------------------------------------------------------------- */

proto._create_panel = function() {
	var p = this.p;
	var el = this.nodes.target;
	var margin = p.width * 0.03;
	var footer_height = 20;
	var border_width = 1;
	// outer frame
	var panel = this._create_div_node();
	panel._resizing = false;
	this._set_styles(panel, {
		borderColor: "#aaaaaa #666666 #666666 #aaaaaa",
		borderStyle: "solid",
		borderWidth: border_width + "px",
		backgroundColor: "#dddddd",
		width: p.width + "px",
		height: p.height + "px",
		position: "absolute",
		overflow: "hidden",
		display: "none",
		zIndex: 1
	});
	//
	var canvas = document.createElement("CANVAS");
	if ( canvas && canvas.getContext ) {
		canvas.width = p.width;
		canvas.height = p.height;
		this._set_styles(canvas, {
			position: "absolute",
			left: "0px",
			top: "0px"
		});
		var ctx = canvas.getContext('2d');
		var grad  = ctx.createLinearGradient(0,0, 0,p.height);
		grad.addColorStop(0, "#ffffff");
		grad.addColorStop(0.05, "#dddddd");
		grad.addColorStop(0.95, "#dddddd");
		grad.addColorStop(1, "#bbbbbb");
		ctx.fillStyle = grad;
		ctx.fillRect(0, 0, p.width, p.height);
		panel.appendChild(canvas);
	} else if(document.uniqueID) {
		var vml = "";
		vml += '<v:rect style="left:-1px; top:0px; width:' + p.width + 'px; height:' + p.height + 'px; position:absolute;" filled="true" stroked="false">';
		vml += '<v:fill type="gradient" color="#bbbbbb" color2="#ffffff" colors="5% #dddddd,95%#dddddd" />';
		vml += '</v:rect>';
		panel.innerHTML = vml;
	}
	this.nodes.panel = panel;
	document.body.appendChild(panel);
	// color palette
	var palette = this._create_div_node();
	this._set_styles(palette, {
		borderColor: "#888888 #ffffff #ffffff #888888",
		borderStyle: "solid",
		borderWidth: border_width + "px",
		backgroundColor: "#dddddd",
		width: ( (p.width - margin * 3) * 0.9 - border_width * 2 ) + "px",
		height: (p.height - footer_height - border_width * 2 - margin * 3) + "px",
		position: "absolute",
		left: margin + "px",
		top: margin + "px",
		overflow: "hidden",
		cursor: "pointer"
	});
	this.nodes.palette = palette;
	this._draw_palette();
	panel.appendChild(palette);
	// lightness bar
	var bar = this._create_div_node();
	this._set_styles(bar, {
		borderColor: "#888888 #ffffff #ffffff #888888",
		borderStyle: "solid",
		borderWidth: border_width + "px",
		backgroundColor: "#dddddd",
		width: ( (p.width - margin * 3) * 0.1 - border_width * 4 ) + "px",
		height: (p.height - footer_height - border_width * 2 - margin * 3) + "px",
		position: "absolute",
		left: ( (p.width - margin * 3) * 0.9 + border_width * 2 + margin * 2 ) + "px",
		top: margin + "px",
		overflow: "hidden",
		cursor: "pointer"
	});
	this.nodes.bar = bar;
	panel.appendChild(bar);
	// palette indicator
	var ie_quirks = false;
	if( document.uniqueID && document.compatMode == "BackCompat" ) {
		ie_quirks = true;
	}
	var pind = this._create_div_node();
	this._set_styles(pind, {
		backgroundColor: "transparent",
		border: "1px solid white",
		width: ie_quirks ? "5px" : "3px",
		height: ie_quirks ? "5px" : "3px",
		position: "absolute",
		left: "0px",
		top: "0px"
	});
	palette.appendChild(pind);
	this.nodes.pind = pind;
	// bar indicator
	var bind = this._create_div_node();
	this._set_styles(bind, {
		backgroundColor: "transparent",
		borderTop: "1px solid #888888",
		borderBottom: "1px solid #ffffff",
		width: bar.style.width,
		height: "5px",
		position: "absolute",
		left: "0px",
		top: "0px"
	});
	//
	var bind2 = this._create_div_node();
	this._set_styles(bind2, {
		backgroundColor: "transparent",
		borderTop: "1px solid #ffffff",
		borderBottom: "1px solid #888888",
		width: "100%",
		height: "3px"
	});
	bind.appendChild(bind2);
	//
	bar.appendChild(bind);
	this.nodes.bind = bind;
	// footer top
	ft_top = (p.height - footer_height - margin) + "px";
	// footer box
	var ft = this._create_div_node();
	this._set_styles(ft, {
		position: "absolute",
		top: ft_top,
		left: palette.style.left,
		width: (p.width - margin * 2) + "px",
		whiteSpace: "nowrap"
	});
	panel.appendChild(ft);
	//
	this._draw_lightness_bar();
	// selected color box
	var cbox = document.createElement("INPUT");
	cbox.type = "text";
	cbox.disabled = true;
	this._set_styles(cbox, {
		width: "30px",
		ackgroundColor: "#dddddd",
		fontFamily: "Arial,sans-serif",
		fontSize: "11px",
		marginRight: "3px",
		verticalAlign: "middle"
	});
	this.nodes.cbox = cbox;
	ft.appendChild(cbox);
	// selected color text box
	var tbox = document.createElement("INPUT");
	tbox.type = "text";
	tbox.maxLength = 7;
	this._set_styles(tbox, {
		width: "50px",
		fontSize: "11px",
		fontFamily: "Arial,sans-serif",
		marginRight: "3px",
		paddingLeft: "3px",
		borderWidth: border_width + "px",
		verticalAlign: "middle"
	});
	this.nodes.tbox = tbox;
	ft.appendChild(tbox);
	// OK button
	var okb = document.createElement("INPUT");
	okb.type = "button";
	okb.value = " O K ";
	this._set_styles(okb, {
		marginTop: "0px",
		marginBottom: "0px",
		marginRight: "3px",
		paddingLeft: "2px",
		paddingRight: "2px",
		fontFamily: "Arial,sans-serif",
		fontSize: "10px",
		verticalAlign: "middle"
	});
	ft.appendChild(okb);
	// Cancel button
	var ccb = document.createElement("INPUT");
	ccb.type = "button";
	ccb.value = "Close";
	this._set_styles(ccb, {
		marginTop: "0px",
		marginBottom: "0px",
		paddingLeft: "2px",
		paddingRight: "2px",
		fontFamily: "Arial,sans-serif",
		fontSize: "10px",
		verticalAlign: "middle"
	});
	ft.appendChild(ccb);
	// set event listeners
	var _this = this;
	_add_event_listener(palette, "mousedown", function(e) { _this._pallet_clicked(e); });
	_add_event_listener(bar, "mousedown", function(e) { _this._lightness_bar_clicked(e); });
	_add_event_listener(okb, "click", function(e) { _this._ok_clicked(e); });
	_add_event_listener(ccb, "click", function(e) { _this._cencel_clicked(e); });
	_add_event_listener(panel, "mousemove", function(e) {
		prevent_default(e);
		stop_propagation(e);
	});
	this._palette_drag_event_prepare();
	this._lightness_bar_drag_event_prepare();
	_add_event_listener(document, "mousedown", function(e) { _this.hide(); });
	_add_event_listener(this.nodes.target, "mousedown", function(e) { stop_propagation(e); });
	_add_event_listener(this.nodes.trigger, "mousedown", function(e) { stop_propagation(e); });
	_add_event_listener(panel, "mousedown", function(e) { stop_propagation(e); });
	_add_event_listener(okb, "mousedown", function(e) { stop_propagation(e); });
	_add_event_listener(ccb, "mousedown", function(e) { stop_propagation(e); });
	//
	return panel;
};

proto._palette_drag_event_prepare = function() {
	var palette = this.nodes.palette;
	var panel = this.nodes.panel;
	palette._dragging = false;
	var mouse_down = function(o, e) {
		prevent_default(e);
		stop_propagation(e);
		o.nodes.palette._dragging = true;
	};
	var mouse_up = function(o, e) {
		prevent_default(e);
		stop_propagation(e);
		o.nodes.palette._dragging = false;
	};
	var mouse_move = function(o, e) {
		if(o.nodes.palette._dragging != true) { return; }
		prevent_default(e);
		stop_propagation(e);
		// clicked coordinates in the palette
		var pos = o._get_mouse_position(e, o.nodes.palette);
		//
		o._pallet_moved(pos.x, pos.y);
	};
	var mouse_move_panel = function(o, e) {
		o.nodes.palette._dragging = false;
	};
	var _this = this;
	_add_event_listener(palette, "mousedown", function(e) { mouse_down(_this, e); });
	_add_event_listener(palette, "mouseup", function(e) { mouse_up(_this, e); });
	_add_event_listener(palette, "mousemove", function(e) { mouse_move(_this, e); });
	_add_event_listener(panel, "mousemove", function(e) { mouse_move_panel(_this, e); });
};

proto._lightness_bar_drag_event_prepare = function() {
	var bar = this.nodes.bar;
	var panel = this.nodes.panel;
	bar._dragging = false;
	var mouse_down = function(o, e) {
		prevent_default(e);
		stop_propagation(e);
		o.nodes.bar._dragging = true;
	};
	var mouse_up = function(o, e) {
		prevent_default(e);
		stop_propagation(e);
		o.nodes.bar._dragging = false;
	};
	var mouse_move = function(o, e) {
		if(o.nodes.bar._dragging != true) { return; }
		prevent_default(e);
		stop_propagation(e);
		var pos = o._get_mouse_position(e, o.nodes.bar);
		o._lightness_bar_moved(pos.y);
	};
	var mouse_move_panel = function(o, e) {
		o.nodes.bar._dragging = false;
	};
	var _this = this;
	_add_event_listener(bar, "mousedown", function(e) { mouse_down(_this, e); });
	_add_event_listener(bar, "mouseup", function(e) { mouse_up(_this, e); });
	_add_event_listener(bar, "mousemove", function(e) { mouse_move(_this, e); });
	_add_event_listener(panel, "mousemove", function(e) { mouse_move_panel(_this, e); });
};

proto._set_styles = function(el, s) {
	for( var k in s ) {
		el.style[k] = s[k];
	}
};

proto._set_indicators = function() {
	var hls = this.hls;
	var nodes = this.nodes;
	// plette indicator
	var pind_w = parseInt( nodes.pind.style.width ) + parseInt( nodes.pind.style.borderLeftWidth ) + parseInt( nodes.pind.style.borderRightWidth );
	var pind_h = parseInt( nodes.pind.style.height ) + parseInt( nodes.pind.style.borderTopWidth ) + parseInt( nodes.pind.style.borderBottomWidth );
	var palette_w = parseInt( nodes.palette.style.width);
	var palette_h = parseInt( nodes.palette.style.height);
	nodes.pind.style.left = ( palette_w * hls.h / 360 - pind_w / 2 ) + "px";
	nodes.pind.style.top = ( palette_h * (1 - hls.s) - pind_h / 2 ) + "px";
	// bar indicator
	var bind_h = parseInt( nodes.bind.style.height ) + parseInt( nodes.bind.style.borderTopWidth ) + parseInt( nodes.bind.style.borderBottomWidth );
	nodes.bind.style.top = ( parseInt(nodes.bar.style.height) * (1 - hls.l) - bind_h / 2 ) + "px";
};

proto._coloring_trigger = function() {
	var tstyle = this.nodes.trigger.style;
	// set background color of the trigger element
	tstyle.backgroundColor = this._conv_rgb_to_css_hex(this.rgb);
	// set font color of the trigger element
	if(this.hls.l > 0.5) {
		tstyle.color = "#000000";
	} else {
		tstyle.color = "#ffffff";
	}
};

proto._ok_clicked = function(e) {
	prevent_default(e);
	stop_propagation(e);
	this.nodes.target.value = this.nodes.tbox.value;
	if(this.p.coloring == true) {
		this._coloring_trigger();
	}
	this.hide();
	this._focus_to_target();
};

proto._cencel_clicked = function(e) {
	prevent_default(e);
	stop_propagation(e);
	this.hide();
	this._focus_to_target();
};

proto._focus_to_target = function() {
	var target = this.nodes.target;
	target.focus();
	// move a cursor to the end of the text in the text box
	var pos = target.value.length;
	if(target.setSelectionRange) {
		// for Firefox,Opera,Safari
		target.setSelectionRange(pos,pos); 
	} else if(target.createTextRange) {
		// for Internet Explorer
		var range = target.createTextRange();
		range.move('character', pos);
		range.select();
	}
};

proto._pallet_clicked = function(e) {
	prevent_default(e);
	stop_propagation(e);
	var p = this.p;
	var nodes = this.nodes;
	// clicked coordinates in the palette
	var pos = this._get_mouse_position(e, nodes.palette);
	//
	this._pallet_moved(pos.x, pos.y);
};

proto._pallet_moved = function(x, y) {
	var palette = this.nodes.palette;
	// set Hue and Saturation
	this.hls.h = x * 359 / parseInt(palette.style.width);
	this.hls.s = 1 - y / parseInt(palette.style.height);
	// set RGB
	this.rgb = this._hls_to_rgb(this.hls);
	// draw the lightness_bar
	this._draw_lightness_bar();
	// move indicators
	this._set_indicators();
	// show selected color infomations
	this._show_selected_color_infomations();
};

proto._lightness_bar_clicked= function(e) {
	//prevent_default(e);
	//stop_propagation(e);
	var p = this.p;
	// clicked coordinates in the palette
	var pos = this._get_mouse_position(e, this.nodes.bar);
	//
	this._lightness_bar_moved(pos.y);
};

proto._get_mouse_position = function(e, el) {
	var elp = this._get_element_abs_pos(el);
	var elx = elp.left;
	var ely = elp.top;

	var de_scroll_left = document.documentElement.scrollLeft;
	var de_scroll_top = document.documentElement.scrollTop;
	var bd_scroll_left = document.body.scrollLeft;
	var bd_scroll_top = document.body.scrollTop;
	var scroll_left = 0;
	var scroll_top = 0;
	if( typeof(de_scroll_left) != "undefined" && de_scroll_left > 0 ) {
		scroll_left = de_scroll_left;
	} else if( typeof(bd_scroll_left) != "undefined" && bd_scroll_left > 0 ) {
		scroll_left = bd_scroll_left;
	}
	if( typeof(de_scroll_top) != "undefined" && de_scroll_top > 0 ) {
		scroll_top = de_scroll_top;
	} else if( typeof(bd_scroll_top) != "undefined" && bd_scroll_top > 0 ) {
		scroll_top = bd_scroll_top;
	}
	//var msx = e.pageX ? e.pageX : scroll_left + e.clientX;
	//var msy = e.pageY ? e.pageY : scroll_top + e.clientY;
	var msx = scroll_left + e.clientX;
	var msy = scroll_top + e.clientY;
	var x = msx - elx;
	var y = msy - ely;
	return {x:x, y:y};
};

proto._lightness_bar_moved= function(y) {
	var bar = this.nodes.bar;
	// set Lightness
	this.hls.l = 1 - y / parseInt(bar.style.height);
	// set RGB
	this.rgb = this._hls_to_rgb(this.hls);
	// move indicators
	this._set_indicators();
	// show selected color infomations
	this._show_selected_color_infomations();
};

proto._show_selected_color_infomations = function() {
	var color = this._conv_rgb_to_css_hex(this.rgb);
	this.nodes.cbox.style.backgroundColor = color;
	this.nodes.tbox.value = color;
};

proto._draw_lightness_bar = function() {
	var el = this.nodes.bar;
	var bind = this.nodes.bind;
	this._clear_child_nodes(el);
	var canvas = document.createElement("CANVAS");
	if ( canvas && canvas.getContext ) {
		this._draw_lightness_bar_by_canvas(canvas);
	} else if(document.uniqueID) {
		this._draw_lightness_bar_by_vml();
	}
	el.appendChild(bind);
};

proto._draw_lightness_bar_by_vml = function() {
	var el = this.nodes.bar;
	this._clear_child_nodes(el);
	var p = this.p;
	var w = parseInt(el.style.width);
	var h = parseInt(el.style.height);
	var hls = { h:this.hls.h, l:this.hls.l, s:this.hls.s };
	//
	hls.l = 0;
	var rgb1 = this._hls_to_rgb(hls);
	var c1 = this._conv_rgb_to_css_hex(rgb1);
	//
	hls.l = 1;
	var rgb2 = this._hls_to_rgb(hls);
	var c2 = this._conv_rgb_to_css_hex(rgb2);
	//
	var vml = "";
	vml += '<v:rect style="left:-1px; top:0px; width:' + w + 'px; height:' + h + 'px; position:absolute;" filled="true" stroked="false">';
	vml += '<v:fill type="gradient" color="' + c1 + '" color2="' + c2 + '" colors="';
	for( var i=1; i<=9; i++ ) {
		hls.l = i / 10;
		var rgb = this._hls_to_rgb(hls);
		var c = this._conv_rgb_to_css_hex(rgb);
		vml += (i*10) + '% ' + c;
		if(i != 9) {
			vml += ',';
		}
	}
	vml += '" />';
	vml += '</v:rect>';
	el.innerHTML = vml;
};

proto._draw_lightness_bar_by_canvas = function(canvas) {
	var el = this.nodes.bar;
	this._clear_child_nodes(el);
	var p = this.p;
	var w = parseInt(el.style.width) + 1;
	var h = parseInt(el.style.height);
	canvas.style.margin = "0px";
	canvas.style.padding = "0px";
	canvas.width = w;
	canvas.height = h;
	el.appendChild(canvas);
	var ctx = canvas.getContext('2d');
	var hls = { h:this.hls.h, l:this.hls.l, s:this.hls.s };
	var grad  = ctx.createLinearGradient(0,0, 0,h);
	for( var i=0; i<=10; i++ ) {
		hls.l = 1 - ( i / 10 );
		var rgb = this._hls_to_rgb(hls);
		var c = this._conv_rgb_to_css(rgb);
		grad.addColorStop(i/10, c);
	}
	ctx.fillStyle = grad;
	ctx.fillRect(0, 0, w, h);
};

proto._draw_palette = function() {
	var canvas = document.createElement("CANVAS");
	if ( canvas && canvas.getContext ) {
		this._draw_palette_by_canvas(canvas);
	} else if(document.uniqueID) {
		this._draw_palette_by_vml();
	}
};

proto._draw_palette_by_vml = function() {
	var el = this.nodes.palette
	var p = this.p;
	var w = parseInt(el.style.width);
	var h = parseInt(el.style.height);
	var hls = {};
	hls.l = 0.5;
	var vml = "";
	var gridw = p.gridie + 1;
	for( var x=-1; x<w; x+=p.gridie ) {
		hls.h = 359 * ( x / w );
		//
		hls.s = 0;
		var rgb1 = this._hls_to_rgb(hls);
		var c1 = this._conv_rgb_to_css_hex(rgb1);
		//
		hls.s = 1;
		var rgb2 = this._hls_to_rgb(hls);
		var c2 = this._conv_rgb_to_css_hex(rgb2);
		//
		vml += '<v:rect style="left:' + x + 'px; top:0px; width:' + gridw + 'px; height:' + h + 'px; position:absolute;" filled="true" stroked="false">';
		vml += '<v:fill type="gradient" color="' + c1 + '" color2="' + c2 + '" colors="';
		for( var i=1; i<=9; i++ ) {
			hls.s = i / 10;
			var rgb = this._hls_to_rgb(hls);
			var c = this._conv_rgb_to_css_hex(rgb);
			vml += (i*10) + '% ' + c;
			if(i != 9) {
				vml += ',';
			}
		}
		vml += '" />';
		vml += '</v:rect>';
	}
	el.innerHTML = vml;
};

proto._draw_palette_by_canvas = function(canvas) {
	var el = this.nodes.palette
	var p = this.p;
	var w = parseInt(el.style.width);
	var h = parseInt(el.style.height);
	canvas.style.margin = "0px";
	canvas.style.padding = "0px";
	canvas.width = w;
	canvas.height = h;
	el.appendChild(canvas);
	//
	var ctx = canvas.getContext('2d');
	var hls = {};
	hls.l = 0.5;
	var gridw = p.grid;
	for( var x=0; x<w; x+=p.grid ) {
		hls.h = 359 * ( x / w );
		var grad  = ctx.createLinearGradient(0,0, 0,h);
		for( var i=0; i<=10; i++ ) {
			hls.s = 1 - ( i / 10 );
			var rgb = this._hls_to_rgb(hls);
			var c = this._conv_rgb_to_css(rgb);
			grad.addColorStop(i/10, c);
		}
		ctx.fillStyle = grad;
		ctx.fillRect(x, 0, gridw, h);
	}
};

proto._clear_child_nodes = function(el) {
	while (el.firstChild) {
		el.removeChild(el.firstChild);
	}
};

proto._create_div_node = function() {
	var node = document.createElement("DIV");
	node.style.margin = "0px";
	node.style.padding = "0px";
	node.style.fontSize = "0px";
	return node;
};

proto._conv_rgb_to_css = function(rgb) {
	if( typeof(rgb.a) == "undefined" ) {
		return "rgb(" + rgb.r + "," + rgb.g + "," + rgb.b + ")";
	} else {
		return "rgba(" + rgb.r + "," + rgb.g + "," + rgb.b + "," + rgb.a + ")";
	}
};

proto._conv_rgb_to_css_hex = function(rgb) {
	var r = rgb.r.toString(16);
	var g = rgb.g.toString(16);
	var b = rgb.b.toString(16);
	if( r.length == 1 ) { r = "0" + r; }
	if( g.length == 1 ) { g = "0" + g; }
	if( b.length == 1 ) { b = "0" + b; }
	return "#" + r + g + b;
};

/* -------------------------------------------------------------------
* http://image-d.isp.jp/commentary/color_cformula/HLS.html
* ----------------------------------------------------------------- */
proto._rgb_to_hls = function(rgb) {
	var R = rgb.r / 255;
	var G = rgb.g / 255;
	var B = rgb.b / 255;
	var MAX = Math.max(R, Math.max(G, B));
	var MIN = Math.min(R, Math.min(G, B));
	var hls = {};
	hls.l = ( MAX + MIN ) / 2;
	if(MAX == MIN) {
		hls.s = 0;
		hls.h = 0;
	} else {
		if(hls.l <= 0.5) {
			hls.s = ( MAX - MIN ) / ( MAX + MIN );
		} else {
			hls.s = ( MAX - MIN ) / ( 2 - MAX - MIN );
		}
		var Cr = ( MAX - R ) / ( MAX - MIN );
		var Cg = ( MAX - G ) / ( MAX - MIN );
		var Cb = ( MAX - B ) / ( MAX - MIN );
		if( R == MAX ) {
			hls.h = Cb - Cg;
		} else if( G == MAX ) {
			hls.h = 2 + Cr - Cb;
		} else if( B = MAX ) {
			hls.h = 4 + Cg - Cr;
		}
		hls.h = 60 * hls.h;
		if(hls.h < 0) {
			hls.h += 360;
		}
	}
	return hls;
};

/* -------------------------------------------------------------------
* http://image-d.isp.jp/commentary/color_cformula/HLS.html
* ----------------------------------------------------------------- */
proto._hls_to_rgb = function(hls) {
	var H = hls.h;	// hue [0-359]
	var L = hls.l;	// lightness [0-1]
	var S = hls.s;	// saturation [0-1]
	var R = 0;	// red [0-1]
	var G = 0;	// green [0-1]
	var B = 0;	// blue [0-1]
	//
	if(S==0) {
		R = L;
		G = L;
		B = L;
	} else {
		var MAX = L*(1+S);
		if( L > 0.5 ) {
			MAX = L*(1-S)+S;
		}
		var MIN = 2 * L - MAX;
		var h = H + 120;
		if( h >= 360 ) { h = h - 360; }
		if( h < 60 ) {
			R = MIN + ( MAX - MIN ) * h / 60;
		} else if( h < 180 ) {
			R = MAX;
		} else if( h < 240 ) {
			R = MIN + ( MAX - MIN ) * ( 240 - h ) / 60;
		} else {
			R = MIN;
		}
		h = H;
		if( h < 60 ) {
			G = MIN + ( MAX - MIN ) * h / 60;
		} else if( h < 180 ) {
			G = MAX;
		} else if( h < 240 ) {
			G = MIN + ( MAX - MIN ) * ( 240 - h ) / 60;
		} else {
			G = MIN;
		}
		h = H - 120;
		if( h < 0 ) { h = h + 360; }
		if( h < 60 ) {
			B = MIN + ( MAX - MIN ) * h / 60;
		} else if( h < 180 ) {
			B = MAX;
		} else if( h < 240 ) {
			B = MIN + ( MAX - MIN ) * ( 240 - h ) / 60;
		} else {
			B = MIN;
		}
	}
	//
	var rgb = {
		r: Math.abs( parseInt(R * 255) ),
		g: Math.abs( parseInt(G * 255) ),
		b: Math.abs( parseInt(B * 255) )
	}
	return rgb;
};

proto._show_element = function(el, speed) {
	var s = el.style;
	if( typeof(speed) == "undefined" ) {
		speed = 0;
	} else {
		speed = parseInt(speed);
	}
	if(speed < 0) {
		speed = 0;
	} else if(speed > 5) {
		speed = 5;
	}
	if(speed == 0) {
		s.display = "";
		return;
	}
	var width = parseInt(s.width);
	var height = parseInt(s.height);
	s.width = "0px";
	s.height = "0px";
	s.display = "";
	var w = 0;
	var h = 0;
	var scale_up = function() {
		el._resizing = true;
		w += ( width * speed / 50 );
		h += ( height * speed / 50 );
		if(w > width) { w = width; }
		if(h > height) { h = height; }
		s.width = w + "px";
		s.height = h + "px";
		if( w < width || h < height ) {
			setTimeout(scale_up, 10);
		} else {
			s.display = "";
			s.width = width + "px";
			s.height = height + "px";
			el._resizing = false;
		}
	};
	scale_up();
};

proto._hide_element = function(el, speed) {
	if( typeof(speed) == "undefined" ) {
		speed = 0;
	} else {
		speed = parseInt(speed);
	}
	if(speed < 0) {
		speed = 0;
	} else if(speed > 5) {
		speed = 5;
	}
	if(speed == 0) {
		el.style.display = "none";
		return;
	}
	var s = el.style;
	var width = parseInt(s.width);
	var height = parseInt(s.height);
	var w = parseInt(width);
	var h = parseInt(height);
	var scale_down = function() {
		el._resizing = true;
		w -= ( width * speed / 50 );
		h -= ( height * speed / 50 );
		if(w < 0) { w = 0; }
		if(h < 0) { h = 0; }
		s.width = w + "px";
		s.height = h + "px";
		if( w > 0 || h > 0 ) {
			setTimeout(scale_down, 10);
		} else {
			s.display = "none";
			s.width = width + "px";
			s.height = height + "px";
			el._resizing = false;
		}
	};
	scale_down();
};

proto._get_element_abs_pos = function(el) {
	var o = {};
	o.left = el.offsetLeft;
	o.top = el.offsetTop;
	var parent = el;
	while(parent.offsetParent) {
		parent = parent.offsetParent;
		o.left += parent.offsetLeft;
		o.top += parent.offsetTop;
	}
	o.width = el.offsetWidth;
	o.height = el.offsetHeight;
	return o;
}

proto._conv_color_to_rgb = function(color) {
	/* color name mapping */
	var color_name_map = {
		aliceblue : "#F0F8FF",
		antiquewhite : "#FAEBD7",
		aqua : "#00FFFF",
		aquamarine : "#7FFFD4",
		azure : "#F0FFFF",
		beige : "#F5F5DC",
		bisque : "#FFE4C4",
		black : "#000000",
		blanchedalmond : "#FFEBCD",
		blue : "#0000FF",
		blueviolet : "#8A2BE2",
		brass : "#B5A642",
		brown : "#A52A2A",
		burlywood : "#DEB887",
		cadetblue : "#5F9EA0",
		chartreuse : "#7FFF00",
		chocolate : "#D2691E",
		coolcopper : "#D98719",
		copper : "#BF00DF",
		coral : "#FF7F50",
		cornflower : "#BFEFDF",
		cornflowerblue : "#6495ED",
		cornsilk : "#FFF8DC",
		crimson : "#DC143C",
		cyan : "#00FFFF",
		darkblue : "#00008B",
		darkbrown : "#DA0B00",
		darkcyan : "#008B8B",
		darkgoldenrod : "#B8860B",
		darkgray : "#A9A9A9",
		darkgreen : "#006400",
		darkkhaki : "#BDB76B",
		darkmagenta : "#8B008B",
		darkolivegreen : "#556B2F",
		darkorange : "#FF8C00",
		darkorchid : "#9932CC",
		darkred : "#8B0000",
		darksalmon : "#E9967A",
		darkseagreen : "#8FBC8F",
		darkslateblue : "#483D8B",
		darkslategray : "#2F4F4F",
		darkturquoise : "#00CED1",
		darkviolet : "#9400D3",
		deeppink : "#FF1493",
		deepskyblue : "#00BFFF",
		dimgray : "#696969",
		dodgerblue : "#1E90FF",
		feldsper : "#FED0E0",
		firebrick : "#B22222",
		floralwhite : "#FFFAF0",
		forestgreen : "#228B22",
		fuchsia : "#FF00FF",
		gainsboro : "#DCDCDC",
		ghostwhite : "#F8F8FF",
		gold : "#FFD700",
		goldenrod : "#DAA520",
		gray : "#808080",
		green : "#008000",
		greenyellow : "#ADFF2F",
		honeydew : "#F0FFF0",
		hotpink : "#FF69B4",
		indianred : "#CD5C5C",
		indigo : "#4B0082",
		ivory : "#FFFFF0",
		khaki : "#F0E68C",
		lavender : "#E6E6FA",
		lavenderblush : "#FFF0F5",
		lawngreen : "#7CFC00",
		lemonchiffon : "#FFFACD",
		lightblue : "#ADD8E6",
		lightcoral : "#F08080",
		lightcyan : "#E0FFFF",
		lightgoldenrodyellow : "#FAFAD2",
		lightgreen : "#90EE90",
		lightgrey : "#D3D3D3",
		lightpink : "#FFB6C1",
		lightsalmon : "#FFA07A",
		lightseagreen : "#20B2AA",
		lightskyblue : "#87CEFA",
		lightslategray : "#778899",
		lightsteelblue : "#B0C4DE",
		lightyellow : "#FFFFE0",
		lime : "#00FF00",
		limegreen : "#32CD32",
		linen : "#FAF0E6",
		magenta : "#FF00FF",
		maroon : "#800000",
		mediumaquamarine : "#66CDAA",
		mediumblue : "#0000CD",
		mediumorchid : "#BA55D3",
		mediumpurple : "#9370DB",
		mediumseagreen : "#3CB371",
		mediumslateblue : "#7B68EE",
		mediumspringgreen : "#00FA9A",
		mediumturquoise : "#48D1CC",
		mediumvioletred : "#C71585",
		midnightblue : "#191970",
		mintcream : "#F5FFFA",
		mistyrose : "#FFE4E1",
		moccasin : "#FFE4B5",
		navajowhite : "#FFDEAD",
		navy : "#000080",
		oldlace : "#FDF5E6",
		olive : "#808000",
		olivedrab : "#6B8E23",
		orange : "#FFA500",
		orangered : "#FF4500",
		orchid : "#DA70D6",
		palegoldenrod : "#EEE8AA",
		palegreen : "#98FB98",
		paleturquoise : "#AFEEEE",
		palevioletred : "#DB7093",
		papayawhip : "#FFEFD5",
		peachpuff : "#FFDAB9",
		peru : "#CD853F",
		pink : "#FFC0CB",
		plum : "#DDA0DD",
		powderblue : "#B0E0E6",
		purple : "#800080",
		red : "#FF0000",
		richblue : "#0CB0E0",
		rosybrown : "#BC8F8F",
		royalblue : "#4169E1",
		saddlebrown : "#8B4513",
		salmon : "#FA8072",
		sandybrown : "#F4A460",
		seagreen : "#2E8B57",
		seashell : "#FFF5EE",
		sienna : "#A0522D",
		silver : "#C0C0C0",
		skyblue : "#87CEEB",
		slateblue : "#6A5ACD",
		slategray : "#708090",
		snow : "#FFFAFA",
		springgreen : "#00FF7F",
		steelblue : "#4682B4",
		tan : "#D2B48C",
		teal : "#008080",
		thistle : "#D8BFD8",
		tomato : "#FF6347",
		turquoise : "#40E0D0",
		violet : "#EE82EE",
		wheat : "#F5DEB3",
		white : "#FFFFFF",
		whitesmoke : "#F5F5F5",
		yellow : "#FFFF00",
		yellowgreen : "#9ACD32"
	};
	if( /^[a-zA-Z]+$/.test(color) && color_name_map[color] ) {
		color = color_name_map[color];
	}
	var rgb = {};
	var m;
	if( m = color.match( /rgb\(\s*(\d+)\,\s*(\d+)\,\s*(\d+)\s*\)/ ) ) {
		rgb.r = parseInt(m[1], 10);
		rgb.g = parseInt(m[2], 10);
		rgb.b = parseInt(m[3], 10);
		rgb.a = 1;
	} else if( m = color.match( /rgba\(\s*(\d+)\,\s*(\d+)\,\s*(\d+),\s*(\d+)\s*\)/ ) ) {
		rgb.r = parseInt(m[1], 10);
		rgb.g = parseInt(m[2], 10);
		rgb.b = parseInt(m[3], 10);
		rgb.a = parseInt(m[4], 10);
	} else if( m = color.match( /\#([a-fA-F0-9]{2})([a-fA-F0-9]{2})([a-fA-F0-9]{2})$/ ) ) {
		rgb.r = parseInt(m[1], 16);
		rgb.g = parseInt(m[2], 16);
		rgb.b = parseInt(m[3], 16);
		rgb.a = 1;
	} else if( m = color.match( /\#([a-fA-F0-9])([a-fA-F0-9])([a-fA-F0-9])$/ ) ) {
		rgb.r = parseInt(m[1]+m[1], 16);
		rgb.g = parseInt(m[2]+m[2], 16);
		rgb.b = parseInt(m[3]+m[3], 16);
		rgb.a = 1;
	} else if( color == "transparent" ) {
		rgb.r = 255;
		rgb.g = 255;
		rgb.b = 255;
		rgb.a = 1;
	} else {
		return null;
	}
	/* for Safari */
	if( rgb.r == 0 && rgb.g == 0 && rgb.b == 0 && rgb.a == 0 ) {
		rgb.r = 255;
		rgb.g = 255;
		rgb.b = 255;
		rgb.a = 1;
	}
	/* */
	return rgb;
};


/* -------------------------------------------------------------------
* for static drawing by class attributes
* ----------------------------------------------------------------- */

_add_event_listener(window, "load", _init);

var cpicks = [];

function _init() {
	var elms = _get_elements_by_class_name(document, "html5jp-cpick");
	var n = 0;
	for( var i=0; i<elms.length; i++ ) {
		var elm = elms.item(i);
		// parse parameters in the class attribute
		var p = {};
		var m = elm.className.match(/\[([^\]]+)\]/);
		if(m && m[1]) {
			var parts = m[1].split(";");
			for( var j=0; j<parts.length; j++ ) {
				var pair = parts[j];
				if(pair == "") { continue; }
				var m2 = pair.match(/^([a-zA-Z0-9\-\_]+)\:([a-zA-Z0-9\-\_\#\(\)\,\.]+)$/);
				if( ! m2 ) { continue; }
				var k = m2[1];
				var v = m2[2];
				p[k] = v;
			}
		}
		// determin the target element
		var target = elm;
		if( typeof(p.target) != "undefined" ) {
			var el = document.getElementById(p.target);
			if( ! el ) { return; }
			target = el;
		}
		// prepare a color cpicker
		_prepare_cpick(p, elm, target);
		//
		n ++;
	}
	if( n > 0 && document.uniqueID ) {
		if (!document.namespaces["v"]) {
			document.namespaces.add("v", "urn:schemas-microsoft-com:vml");
			var style_sheet = document.createStyleSheet();
			style_sheet.cssText = "v\\:rect, v\\:fill { behavior: url(#default#VML); display:inline-block; }";
		}
	}
}

function _prepare_cpick(p, trigger, target) {
	// color picker object
	var o = new cpick(trigger, target, p);
	if( ! o ) { return; }
	cpicks.push(o);
	o.prepare();
	// set event listeners
	_add_event_listener(trigger, "click", function(){
		for( var i=0; i<cpicks.length; i++ ) {
			if(cpicks[i] == o) { continue; }
			cpicks[i].hide();
		}
		o.flip();
	});
}

function _add_event_listener(elm, type, func) {
	if(! elm) { return false; }
	if(elm.addEventListener) {
		elm.addEventListener(type, func, false);
	} else if(elm.attachEvent) {
		elm.attachEvent('on'+type, func);
		/*
		elm['e'+type+func] = func;
		elm[type+func] = function(){elm['e'+type+func]( window.event );}
		elm.attachEvent( 'on'+type, elm[type+func] );
		*/
	} else {
		return false;
	}
	return true;
}

function _get_elements_by_class_name(element, classNames) {
	if(element.getElementsByClassName) {
		return element.getElementsByClassName(classNames);
	}
	/* split a string on spaces */
	var split_a_string_on_spaces = function(string) {
		string = string.replace(/^[\t\s]+/, "");
		string = string.replace(/[\t\s]+$/, "");
		var tokens = string.split(/[\t\s]+/);
		return tokens;
	};
	var tokens = split_a_string_on_spaces(classNames);
	var tn = tokens.length;
	var nodes = element.all ? element.all : element.getElementsByTagName("*");
	var n = nodes.length;
	var array = new Array();
	if( tn > 0 ) {
		if( document.evaluate ) {
			var contains = new Array();
			for(var i=0; i<tn; i++) {
				contains.push('contains(concat(" ",@class," "), " '+ tokens[i] + '")');
			}
			var xpathExpression = "/descendant::*[" + contains.join(" and ") + "]";
			var iterator = document.evaluate(xpathExpression, element, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
			var inum = iterator.snapshotLength;
			for( var i=0; i<inum; i++ ) {
				var elm = iterator.snapshotItem(i);
				if( elm != element ) {
					array.push(iterator.snapshotItem(i));
				}
			}
		} else {
			for(var i=0; i<n; i++) {
				var elm = nodes.item(i);
				if( elm.className == "" ) { continue; }
				var class_list = split_a_string_on_spaces(elm.className);
				var class_name = class_list.join(" ");
				var f = true;
				for(var j=0; j<tokens.length; j++) {
					var re = new RegExp('(^|\\s)' + tokens[j] + '(\\s|$)')
					if( ! re.test(class_name) ) {
						f = false;
						break;
					}
				}
				if(f == true) {
					array.push(elm);
				}
			}
		}
	}
	/* add item(index) method to the array as if it behaves such as a NodeList interface. */
	array.item = function(index) {
		if(array[index]) {
			return array[index];
		} else {
			return null;
		}
	};
	//
	return array;
}

function prevent_default(evt) {
	if(evt && evt.preventDefault) {
		evt.preventDefault();
		evt.currentTarget['on'+evt.type] = function() {return false;};
	} else if(window.event) {
		window.event.returnValue = false;
	}
}

function stop_propagation(evt) {
	if(evt && evt.stopPropagation) {
		evt.stopPropagation();
	} else if(window.event) {
		window.event.cancelBubble = true;
	}
}

})();
