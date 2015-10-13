<?php include 'header.php'; ?>
		<h2>Strømforbruget på Studentergården</h2>
		<p>Dette er et forsøg. Studentergården får strøm fra to målerskabe - det ene sidder i rummet med opvaskemiddel, det andet sidder over for kostumekælderen.<br>
			Graferne herunder viser det aktuelle strømforbrug for de to skabe og tilsammen giver de hele SG's strømforbrug de sidste tyve minutter.<br>
			Ved at trykke på <a href="/history.html">Get history</a> kan strømforbruget ses vilkårligt langt tilbage. Denne funktion virker kun for Fensmarksgadefløjen.<br>
            God fornøjelse :) <br><br>
            PS. Du kan nå denne side ved at skrive <a href="http://power/">power/</a> eller <a href="http://power.studentergaarden.dk">power.studentergaarden.dk</a> i din browser.
		</p>

		<h3>Opsummering</h3>
		Sidste dag
		Sidste uge
		Sidste måned
		Sidste År
		Samme uge sidste år \ %-vis forskel
		Samme måned sidste år \ %-vis forskel

		<h4>Fensmarksgade</h4>
		<h4>Arresøgade</h4>
		
		<h3>Målinger for Fensmarksgade-fløjen</h3>
		<div class="livegraph" value="0" style="width:800px;height:400px;"></div>
		<h4>Last update:</h4>
		<p><pre id="text1"></pre></p>
		<p><pre id="textUsage1"></pre></p>


		<h3>Målinger for Arresøgade-fløjen</h3>
		<div class="livegraph" value="1" style="width:800px;height:400px;"></div>
		<h4>Last update:</h4>
		<p><pre id="text2"></pre></p>
		<p><pre id="textUsage2"></pre></p>


		<h3>Ugeforbrug for Fensmarksgade-fløjen</h3>
		<div class="weekgraph" value="0" style="width:1200px;height:400px;"></div>
		<h4>This weeks usage:</h4>
		<p><pre id="textWeekUsage1"></pre></p>

		<h3>Ugeforbrug for Arresøgade-fløjen</h3>
		<div class="weekgraph" value="1" style="width:1200px;height:400px;"></div>
		<h4>This weeks usage:</h4>
		<p><pre id="textWeekUsage2"></pre></p>


		<h3>Månedsforbrug for Fensmarksgade-fløjen</h3>
		<div class="monthgraph" value="0" style="width:1200px;height:400px;"></div>
		<h4>This months usage:</h4>
		<p><pre id="textMonthUsage1"></pre></p>

		<h3>Månedsforbrug for Arresøgade-fløjen</h3>
		<div class="monthgraph" value="1" style="width:1200px;height:400px;"></div>
		<h4>This months usage:</h4>
		<p><pre id="textMonthUsage2"></pre></p>
<?php include 'footer.php'; ?>
