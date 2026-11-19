import UIKit

final class BallView: UIView {
    override var collisionBoundsType: UIDynamicItemCollisionBoundsType {
        return .ellipse
    }
}

final class ViewController: UIViewController, UICollisionBehaviorDelegate {
    
    // MARK: Configuración
    private let ballSize: CGFloat = 20
    
    // Cambiamos ballSpeed y paddleSize de 'let' a 'var' para poder modificarlos dinámicamente:
    private var ballSpeed: CGFloat = 420
    private var paddleSize = CGSize(width: 100, height: 16)
    
    private let rows = 5
    private let cols = 7
    private let brickColors: [UIColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue]
     
    // MARK: Vistas
    private let paddle = UIView()
    private let ball = BallView()
    private var bricks: [String: UIView] = [:]
    
    private var brickHits: [String: Int] = [:]        // Golpes restantes por ladrillo
    
    private let scoreLabel = UILabel()
    private let livesLabel = UILabel()
    private let messageLabel = UILabel()
    private let topLine = UIView()
     
    // MARK: Física
    private var animator: UIDynamicAnimator!
    private var collision: UICollisionBehavior!
    private var ballBehavior: UIDynamicItemBehavior!
    private var gravity: UIGravityBehavior!
    private var debrisBehavior: UIDynamicItemBehavior!
     
    // MARK: Estado
    private var score = 0
    private var lives = 3
    private var ballInPlay = false
    private var isGameOver = false
    
    private var activePowerUps: [UIView] = []         // Power-ups cayendo
    private var currentLevel = 1
    private var paddleExpandTimer: Timer?
    private let highScoreKey = "BreakoutHighScore"

    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.07, green: 0.09, blue: 0.15, alpha: 1)
        setupHUD()
        
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        view.addGestureRecognizer(pan)
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        view.addGestureRecognizer(tap)
    }
    
    private func setupHUD() {
        for label in [scoreLabel, livesLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 20, weight: .bold)
            label.textColor = .white
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
        }
        messageLabel.font = .systemFont(ofSize: 28, weight: .heavy)
        messageLabel.textColor = .white
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(messageLabel)
     
        topLine.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        topLine.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topLine)
     
        NSLayoutConstraint.activate([
            scoreLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            scoreLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            livesLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            livesLabel.centerYAnchor.constraint(equalTo: scoreLabel.centerYAnchor),
            topLine.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topLine.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topLine.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 55),
            topLine.heightAnchor.constraint(equalToConstant: 1),
            messageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 60),
            messageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20)
        ])
        updateHUD()
    }
     
    private func updateHUD() {
        scoreLabel.text = "Puntos: \(score)"
        livesLabel.text = "Vidas: \(lives)"
    }
    
    private func showMessage(_ text: String) {
        messageLabel.text = text
        messageLabel.alpha = 0
        messageLabel.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        UIView.animate(withDuration: 0.5, delay: 0,
                       usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5,
                       options: [], animations: {
            self.messageLabel.alpha = 1
            self.messageLabel.transform = .identity
        }, completion: nil)
    }
     
    private func hideMessage() {
        UIView.animate(withDuration: 0.2) {
            self.messageLabel.alpha = 0
        }
    }
    
    private func pulse(_ v: UIView) {
        UIView.animateKeyframes(withDuration: 0.3, delay: 0, options: [], animations: {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.5) {
                v.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.5, relativeDuration: 0.5) {
                v.transform = .identity
            }
        }, completion: nil)
    }
     
    private func shake(_ v: UIView) {
        UIView.animateKeyframes(withDuration: 0.4, delay: 0, options: [], animations: {
            let offsets: [CGFloat] = [-10, 10, -6, 6, 0]
            for (i, dx) in offsets.enumerated() {
                UIView.addKeyframe(withRelativeStartTime: Double(i) / 5, relativeDuration: 0.2) {
                    v.transform = CGAffineTransform(translationX: dx, y: 0)
                }
            }
        }, completion: nil)
    }
    
    private var playArea: CGRect {
        let top = view.safeAreaInsets.top + 56
        return CGRect(x: 0, y: top, width: view.bounds.width, height: view.bounds.height - top)
    }
    
    private func setupGame() {
        animator = UIDynamicAnimator(referenceView: view)
     
        collision = UICollisionBehavior(items: [])
        collision.collisionDelegate = self
        animator.addBehavior(collision)
     
        ballBehavior = UIDynamicItemBehavior(items: [])
        ballBehavior.elasticity = 1
        ballBehavior.friction = 0
        ballBehavior.resistance = 0
        ballBehavior.allowsRotation = false
        animator.addBehavior(ballBehavior)
        
        gravity = UIGravityBehavior(items: [])
        gravity.magnitude = 1.5
        animator.addBehavior(gravity)
         
        debrisBehavior = UIDynamicItemBehavior(items: [])
        debrisBehavior.allowsRotation = true
        animator.addBehavior(debrisBehavior)
        
        collision.action = { [weak self] in
            self?.gameTick()
        }
     
        addWalls()
        addPaddle()
        addBall()
        buildBricks()
        showMessage("Toca para lanzar")
    }
    
    private func addWalls() {
        let a = playArea
        let bottom = a.maxY + 300 // las paredes laterales siguen hacia abajo; no hay piso
        collision.addBoundary(withIdentifier: "left" as NSString,
                              from: CGPoint(x: a.minX, y: bottom), to: CGPoint(x: a.minX, y: a.minY))
        collision.addBoundary(withIdentifier: "top" as NSString,
                              from: CGPoint(x: a.minX, y: a.minY), to: CGPoint(x: a.maxX, y: a.minY))
        collision.addBoundary(withIdentifier: "right" as NSString,
                              from: CGPoint(x: a.maxX, y: a.minY), to: CGPoint(x: a.maxX, y: bottom))
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if animator == nil { setupGame() }
    }
    
    private func addPaddle() {
        let y = view.bounds.height - view.safeAreaInsets.bottom - 50
        paddle.frame = CGRect(x: (view.bounds.width - paddleSize.width) / 2, y: y,
                              width: paddleSize.width, height: paddleSize.height)
        paddle.backgroundColor = .systemTeal
        paddle.layer.cornerRadius = paddleSize.height / 2
        view.addSubview(paddle)
        updatePaddleBoundary()
    }
     
    private func updatePaddleBoundary() {
        collision.removeBoundary(withIdentifier: "paddle" as NSString)
        collision.addBoundary(withIdentifier: "paddle" as NSString,
                              for: UIBezierPath(roundedRect: paddle.frame, cornerRadius: paddleSize.height / 2))
    }
    
    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        guard animator != nil, !isGameOver else { return }
        let half = paddle.bounds.width / 2
        let x = g.location(in: view).x
        paddle.center.x = min(max(x, half), view.bounds.width - half)
        updatePaddleBoundary()
        if !ballInPlay { placeBallOnPaddle() }
    }
    
    private func addBall() {
        ball.frame = CGRect(x: 0, y: 0, width: ballSize, height: ballSize)
        ball.backgroundColor = .white
        ball.layer.cornerRadius = ballSize / 2
        view.addSubview(ball)
        placeBallOnPaddle()
    }
     
    private func placeBallOnPaddle() {
        ball.center = CGPoint(x: paddle.center.x, y: paddle.frame.minY - ballSize / 2 - 2)
    }
    
    private func launchBall() {
        ballInPlay = true
        hideMessage()
        collision.addItem(ball)
        ballBehavior.addItem(ball)
     
        let angle = CGFloat.random(in: -0.4...0.4)
        let velocity = CGPoint(x: ballSpeed * sin(angle), y: -ballSpeed * cos(angle))
        ballBehavior.addLinearVelocity(velocity, for: ball)
    }
    
    @objc private func handleTap() {
        guard animator != nil else { return }
        if isGameOver {
            restartGame()
            return
        }
        guard !ballInPlay else { return }
        launchBall()
    }
    
    private func gameTick() {
        guard ballInPlay else { return }
        
        checkPowerUps()
        
        if ball.frame.minY > view.bounds.maxY {
            DispatchQueue.main.async { self.loseLife() }
            return
        }
     
        let v = ballBehavior.linearVelocity(for: ball)
        guard hypot(v.x, v.y) > 1 else { return }
        var dx = v.x
        var dy = v.y
        let minVertical = ballSpeed * 0.3
        if abs(dy) < minVertical { dy = (dy >= 0 ? 1 : -1) * minVertical }
        let k = ballSpeed / hypot(dx, dy)
        dx *= k
        dy *= k
        ballBehavior.addLinearVelocity(CGPoint(x: dx - v.x, y: dy - v.y), for: ball)
    }
    
    private func buildBricks() {
        for (id, brick) in bricks {
            collision.removeBoundary(withIdentifier: id as NSString)
            brick.removeFromSuperview()
        }
        bricks.removeAll()
     
        let a = playArea
        let margin: CGFloat = 10
        let spacing: CGFloat = 6
        let width = (a.width - margin * 2 - spacing * CGFloat(cols - 1)) / CGFloat(cols)
        let height: CGFloat = 22
     
        for r in 0..<rows {
            for c in 0..<cols {
                let frame = CGRect(x: margin + CGFloat(c) * (width + spacing),
                                   y: a.minY + 40 + CGFloat(r) * (height + spacing),
                                   width: width, height: height)
                let brick = UIView(frame: frame)
                brick.backgroundColor = brickColors[r % brickColors.count]
                brick.layer.cornerRadius = 4
                view.insertSubview(brick, belowSubview: messageLabel)
     
                let id = "brick-\(r)-\(c)"
                bricks[id] = brick
                collision.addBoundary(withIdentifier: id as NSString, for: UIBezierPath(rect: frame))
     
                brick.alpha = 0
                brick.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
                UIView.animate(withDuration: 0.5,
                               delay: Double(r * cols + c) * 0.015,
                               usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5,
                               options: [], animations: {
                    brick.alpha = 1
                    brick.transform = .identity
                }, completion: nil)
                
                let hits = (r < 2) ? 2 : 1 // Filas superiores requieren 2 golpes
                brickHits[id] = hits
                brick.backgroundColor = (hits == 2) ? .systemPurple : brickColors[r % brickColors.count]
            }
        }
    }
    
    func collisionBehavior(_ behavior: UICollisionBehavior,
                           beganContactFor item: UIDynamicItem,
                           withBoundaryIdentifier identifier: NSCopying?,
                           at p: CGPoint) {
        guard let id = identifier as? String else { return }
        DispatchQueue.main.async {
            if id == "paddle" {
                self.bounceOffPaddle(at: p)
            } else if id.hasPrefix("brick-") {
                self.breakBrick(id: id)
            }
        }
    }
    
    private func bounceOffPaddle(at p: CGPoint) {
        guard ballInPlay else { return }
        let offset = (p.x - paddle.center.x) / (paddle.bounds.width / 2)   // de -1 a 1
        let angle = max(-1, min(1, offset)) * (.pi / 3)                  // hasta 60°
        let desired = CGPoint(x: ballSpeed * sin(angle), y: -ballSpeed * cos(angle))
        let v = ballBehavior.linearVelocity(for: ball)
        ballBehavior.addLinearVelocity(CGPoint(x: desired.x - v.x, y: desired.y - v.y), for: ball)
    }
    
    private func breakBrick(id: String) {
        guard let brick = bricks[id] else { return }
        // Ladrillo de dos golpes: primer impacto cambia de color con UIView.transition
        if let remaining = brickHits[id], remaining > 1 {
            brickHits[id] = remaining - 1
            UIView.transition(with: brick, duration: 0.25, options: .transitionFlipFromTop, animations: {
                brick.backgroundColor = .systemCyan
            }, completion: nil)
            return
        }
        
        // Segundo impacto (o ladrillo de 1 golpe): se rompe
        bricks.removeValue(forKey: id)
        brickHits.removeValue(forKey: id)
        collision.removeBoundary(withIdentifier: id as NSString)

        score += 10
        updateHUD()
        pulse(scoreLabel)
        
        // 20% de probabilidad de soltar un Power-Up
        if Int.random(in: 1...100) <= 20 {
            spawnPowerUp(at: brick.center)
        }

        gravity.addItem(brick)
        debrisBehavior.addItem(brick)
        debrisBehavior.addAngularVelocity(CGFloat.random(in: -8...8), for: brick)

        let push = UIPushBehavior(items: [brick], mode: .instantaneous)
        push.setAngle(CGFloat.random(in: -CGFloat.pi...0), magnitude: 0.3)
        animator.addBehavior(push)

        UIView.animate(withDuration: 0.8, delay: 0.3, options: [], animations: {
            brick.alpha = 0
        }, completion: { _ in
            self.gravity.removeItem(brick)
            self.debrisBehavior.removeItem(brick)
            self.animator.removeBehavior(push)
            brick.removeFromSuperview()
        })

        if bricks.isEmpty { nextLevel() }
    }
    
    private func loseLife() {
        guard ballInPlay else { return }
        stopBall()
        lives -= 1
        updateHUD()
        shake(livesLabel)
     
        if lives == 0 {
            endGame(won: false)
        } else {
            placeBallOnPaddle()
            showMessage("Toca para lanzar")
        }
    }
     
    private func stopBall() {
        ballInPlay = false
        collision.removeItem(ball)
        ballBehavior.removeItem(ball)
    }
    
    private func endGame(won: Bool) {
        if ballInPlay { stopBall() }
        isGameOver = true
        placeBallOnPaddle()
        
        let savedHigh = UserDefaults.standard.integer(forKey: highScoreKey)
        let bestScore = max(score, savedHigh)
        if score > savedHigh {
            UserDefaults.standard.set(score, forKey: highScoreKey)
        }
        
        let title = won ? "¡Ganaste! 🎉" : "Game Over"
        showMessage("\(title)\nPuntos: \(score) | Récord: \(bestScore)\nToca para jugar de nuevo")
    }
     
    private func restartGame() {
        score = 0
        lives = 3
        currentLevel = 1
        ballSpeed = 420
        isGameOver = false
        updateHUD()
        buildBricks()
        placeBallOnPaddle()
        showMessage("Toca para lanzar")
    }
    
    private func spawnPowerUp(at center: CGPoint) {
        let powerUp = UIView(frame: CGRect(x: 0, y: 0, width: 22, height: 22))
        powerUp.center = center
        powerUp.backgroundColor = .systemPink
        powerUp.layer.cornerRadius = 11
        powerUp.layer.borderWidth = 2
        powerUp.layer.borderColor = UIColor.white.cgColor
        view.addSubview(powerUp)
        
        activePowerUps.append(powerUp)
        gravity.addItem(powerUp)
    }

    private func checkPowerUps() {
        for (index, p) in activePowerUps.enumerated().reversed() {
            if p.frame.intersects(paddle.frame) {
                // Toca la paleta: eliminar power-up y agrandar paleta por 10s
                gravity.removeItem(p)
                p.removeFromSuperview()
                activePowerUps.remove(at: index)
                expandPaddleFor10Seconds()
            } else if p.frame.minY > view.bounds.maxY {
                gravity.removeItem(p)
                p.removeFromSuperview()
                activePowerUps.remove(at: index)
            }
        }
    }

    private func expandPaddleFor10Seconds() {
        paddleExpandTimer?.invalidate()
        paddleSize.width = 160
        
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.6, options: [], animations: {
            let center = self.paddle.center
            self.paddle.frame.size.width = self.paddleSize.width
            self.paddle.center = center
            self.paddle.backgroundColor = .systemGreen
        }, completion: { _ in
            self.updatePaddleBoundary()
        })
        
        paddleExpandTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.paddleSize.width = 100
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5, options: [], animations: {
                let center = self.paddle.center
                self.paddle.frame.size.width = self.paddleSize.width
                self.paddle.center = center
                self.paddle.backgroundColor = .systemTeal
            }, completion: { _ in
                self.updatePaddleBoundary()
            })
        }
    }
    
    private func nextLevel() {
        stopBall()
        currentLevel += 1
        ballSpeed *= 1.15 // Aumenta velocidad 15%
        buildBricks()
        placeBallOnPaddle()
        showMessage("¡Nivel \(currentLevel)! 🚀\nVelocidad +15%\nToca para lanzar")
    }
}
