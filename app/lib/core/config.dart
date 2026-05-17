class BacktestConfig {
  final double initialCash;
  final double takerFeePct;
  final double slippagePct;
  final bool fillOnNextOpen;
  final int maxOpenPositions;
  final double? maxDrawdownHaltPct;
  final double? stopLossPct;

  const BacktestConfig({
    this.initialCash = 10000.0,
    this.takerFeePct = 0.1,
    this.slippagePct = 0.05,
    this.fillOnNextOpen = true,
    this.maxOpenPositions = 5,
    this.maxDrawdownHaltPct,
    this.stopLossPct,
  });

  double applyBuySlippage(double price) => price * (1 + slippagePct / 100);
  double applySellSlippage(double price) => price * (1 - slippagePct / 100);
  double computeFee(double notional) => notional * takerFeePct / 100;
}
