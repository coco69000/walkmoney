
$file = "lib\main.dart"
$content = Get-Content $file -Raw
$startStr = " void _showGainDetailsDialog(BuildContext context) async {"

$start = $content.IndexOf($startStr)
$count = 0
$end = -1
for ($i = $start; $i -lt $content.Length; $i++) {
    if ($content[$i] -eq "{") { $count++ }
    elseif ($content[$i] -eq "}") {
        $count--
        if ($count -eq 0) {
            $end = $i
            break
        }
    }
}

$oldText = $content.Substring($start, $end - $start + 1)
$newText = " void _showGainDetailsDialog(BuildContext context) async {
    int finalTotal = await widget.calculateDynamicReward(widget.challenge, _selectedTravelType);

    double baseEffort = widget.challenge.rewardLame.toDouble();
    double totalBase = baseEffort;

    int stayMin = 0;
    double stayBonus = 0;
    if (widget.challenge.stayDurationSeconds != null && widget.challenge.stayDurationSeconds! > 0) {
      stayMin = (widget.challenge.stayDurationSeconds! / 60).round();
      stayBonus = stayMin.toDouble();
      if (stayMin > 3) stayBonus += (stayMin - 3);
    }
    totalBase += stayBonus;

    int visitCount = widget.challenge.visitCount ?? 1;
    if (visitCount > 1) {
      totalBase = totalBase * 2 * visitCount;
    }

    double weatherBonus = 0;
    String weatherBonusText = `"Aucun`";
    final weather = widget.weatherData;
    if (weather != null) {
      bool isBadWeather = weather.weatherCode >= 51 || weather.weatherCode == 45 || weather.weatherCode == 48;
      bool isExtremeTemp = weather.temperature < 2 || weather.temperature > 32;
      if (isBadWeather || isExtremeTemp || weather.windSpeed > 30) {
        weatherBonus = totalBase * 0.5;
        weatherBonusText = `"+`$(`${weatherBonus.round()}) L (x1.5)`";
        totalBase += weatherBonus;
      }
    }

    double adBonus = 0;
    String adBonusText = `"Aucun`";
    if (widget.userProfile.adPoints >= 10) {
      adBonus = totalBase * 0.2;
      adBonusText = `"+`$(`${adBonus.round()}) L (x1.2)`";
      totalBase += adBonus;
    }

    double vipBonus = 0;
    String vipBonusText = `"Aucun`";
    if (widget.userProfile.isVip) {
      vipBonus = totalBase * 0.15;
      vipBonusText = `"+`$(`${vipBonus.round()}) L (x1.15)`";
      totalBase += vipBonus;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Center(
                child: Text(`"Détail de la Récompense`",
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: primaryGreen, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 20),
              
              _buildDetailRowDialog(`"Récompense du défi :`", `"`$(`${baseEffort.round()}) L`"),
              if (stayBonus > 0) _buildDetailRowDialog(`"Bonus Temps sur place (`$stayMin min) :`", `"+`$(`${stayBonus.round()}) L`"),
              if (visitCount > 1) _buildDetailRowDialog(`"Multi-visites (x`$visitCount) :`", `"x2 / visite`"),
              
              const Divider(height: 30),
              _buildSectionHeader(`"Boosts Multiplicateurs`"),
              _buildDetailRowDialog(`"Météo Difficile :`", weatherBonusText, isBonus: weatherBonus > 0),
              _buildDetailRowDialog(`"Bonus Soutien (+10 Ad Points) :`", adBonusText, isBonus: adBonus > 0),
              _buildDetailRowDialog(`"Bonus Premium VIP :`", vipBonusText, isBonus: vipBonus > 0),
              
              const Divider(height: 30),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: primaryGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(15)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(`"Gain Total estimé :`", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryGreen)),
                    Text(`"+ `$finalTotal L`", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: primaryGreen)),
                  ],
                ),
              ),
              const SizedBox(height: 15),
              const Text(`"?? Le gain de trajet (distance parcourue) vous est maintenant crédité séparément dès votre arrivée !`",
                style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }"

$content = $content.Replace($oldText, $newText)
Set-Content $file $content

