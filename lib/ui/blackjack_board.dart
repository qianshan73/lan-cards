import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ddz_cards.dart';

/// Renders a filtered host snapshot; the dealer and scoring live in rules.
class BlackjackBoard extends StatelessWidget {
  const BlackjackBoard({
    super.key,
    required this.game,
    required this.playerId,
    required this.turnName,
    required this.canAct,
    required this.onAction,
  });

  final Map<String, dynamic> game;
  final String playerId;
  final String turnName;
  final bool canAct;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final hand = (game['hand'] as List).cast<int>();
    final dealer = [
      ...(game['dealerCards'] as List).cast<int>(),
      if (game['dealerHidden'] == true) -1,
    ];
    final finished = game['finished'] == true;
    final outcome = (game['outcomes'] as Map)[playerId] as Map?;
    final actions = game['availableActions'] as List;
    final headline = finished
        ? game['voided'] == true
              ? '本局作废'
              : '${outcome?['label'] ?? '已结算'} · ${_points(outcome?['points'] as int? ?? 0)}'
        : game['turnPlayer'] == playerId
        ? '轮到你：要牌或停牌'
        : '等待 $turnName 操作';
    final dealerLabel = game['dealerHidden'] == true
        ? '庄家 · 明牌 ${game['dealerTotal']} 点'
        : '庄家 · ${game['dealerTotal']} 点';
    final handLabel = game['natural'] == true
        ? '你的手牌 · 天生 21 点'
        : '你的手牌 · ${game['total']} 点';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF195542),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDEBA75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              headline,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFFFDA92),
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final house = _Hand(label: dealerLabel, cards: dealer);
              final player = _Hand(label: handLabel, cards: hand);
              if (constraints.maxWidth < 360) {
                return Column(
                  children: [house, const SizedBox(height: 12), player],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: house),
                  const SizedBox(width: 16),
                  Expanded(child: player),
                ],
              );
            },
          ),
          if (!finished) ...[
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: const ValueKey('blackjack-hit'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEAB66B),
                    foregroundColor: const Color(0xFF382B17),
                    minimumSize: const Size(90, 42),
                  ),
                  onPressed: canAct && actions.contains('hit')
                      ? () => onAction('hit')
                      : null,
                  child: const Text('要牌'),
                ),
                OutlinedButton(
                  key: const ValueKey('blackjack-stand'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFD4E1D9)),
                    minimumSize: const Size(90, 42),
                  ),
                  onPressed: canAct && actions.contains('stand')
                      ? () => onAction('stand')
                      : null,
                  child: const Text('停牌'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _points(int value) => '${value > 0 ? '+' : ''}$value 分';
}

class _Hand extends StatelessWidget {
  const _Hand({required this.label, required this.cards});
  final String label;
  final List<int> cards;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white),
      ),
      const SizedBox(height: 6),
      LayoutBuilder(
        builder: (context, constraints) {
          final width = math.min(42.0, constraints.maxWidth);
          final step = cards.length < 2
              ? 0.0
              : math.min(
                  width + 4,
                  (constraints.maxWidth - width) / (cards.length - 1),
                );
          return Center(
            child: SizedBox(
              width: width + step * math.max(0, cards.length - 1),
              height: 57,
              child: Stack(
                children: [
                  for (var i = 0; i < cards.length; i++)
                    Positioned(
                      left: i * step,
                      width: width,
                      height: 57,
                      child: Semantics(
                        label: cards[i] < 0 ? '庄家暗牌' : ddzCardLabel(cards[i]),
                        child: DdzCardFace(card: cards[i]),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ],
  );
}
